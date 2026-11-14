// JNI bridge between com.livingai.core.ai.LlamaNative and llama.cpp.
//
// One Session = one loaded GGUF model + one context. Text crosses the boundary as UTF-8 byte
// arrays (never as Java "modified UTF-8"), so Thai and emoji survive intact.
// The session remembers which tokens are in the context; a new prompt that starts with the same
// tokens (system prompt, earlier turns) only evaluates the part that changed.

#include <jni.h>
#include <atomic>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "llama.h"

#ifdef __ANDROID__
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "KivoLlama", __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) do { fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } while (0)
#endif

namespace {

struct Session {
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
    const llama_vocab *vocab = nullptr;
    std::vector<llama_token> cached;      // tokens currently in the context (KV cache)
    std::atomic<bool> abort{false};
    std::mutex lock;                      // one generation at a time
    // statistics of the last generation
    int promptTokens = 0, reusedTokens = 0, outTokens = 0;
    double promptMs = 0, genMs = 0;
};

std::once_flag backendOnce;
std::atomic<bool> quiet{true};

void logCallback(ggml_log_level level, const char *text, void *) {
    if (quiet.load() && level < GGML_LOG_LEVEL_ERROR) return;
#ifdef __ANDROID__
    __android_log_write(level >= GGML_LOG_LEVEL_ERROR ? ANDROID_LOG_ERROR : ANDROID_LOG_INFO, "llama", text);
#else
    fputs(text, stderr);
#endif
}

std::string bytesToString(JNIEnv *env, jbyteArray arr) {
    if (!arr) return {};
    jsize n = env->GetArrayLength(arr);
    std::string s((size_t) n, '\0');
    if (n > 0) env->GetByteArrayRegion(arr, 0, n, reinterpret_cast<jbyte *>(&s[0]));
    return s;
}

jbyteArray stringToBytes(JNIEnv *env, const std::string &s) {
    jbyteArray out = env->NewByteArray((jsize) s.size());
    if (out && !s.empty()) env->SetByteArrayRegion(out, 0, (jsize) s.size(), reinterpret_cast<const jbyte *>(s.data()));
    return out;
}

std::vector<llama_token> tokenize(const llama_vocab *vocab, const std::string &text, bool addSpecial, bool parseSpecial) {
    std::vector<llama_token> tokens(text.size() + 16);
    int n = llama_tokenize(vocab, text.data(), (int32_t) text.size(), tokens.data(), (int32_t) tokens.size(), addSpecial, parseSpecial);
    if (n < 0) {
        tokens.resize((size_t) -n);
        n = llama_tokenize(vocab, text.data(), (int32_t) text.size(), tokens.data(), (int32_t) tokens.size(), addSpecial, parseSpecial);
    }
    tokens.resize(n < 0 ? 0 : (size_t) n);
    return tokens;
}

std::string piece(const llama_vocab *vocab, llama_token token) {
    char buf[256];
    int n = llama_token_to_piece(vocab, token, buf, sizeof(buf), 0, false);
    if (n < 0) {
        std::string big((size_t) -n, '\0');
        n = llama_token_to_piece(vocab, token, &big[0], (int32_t) big.size(), 0, false);
        return n > 0 ? big.substr(0, (size_t) n) : std::string();
    }
    return std::string(buf, (size_t) n);
}

double nowMs() { return (double) ggml_time_us() / 1000.0; }

// stop reasons, mirrored in LlamaNative
const int STOP_EOS = 0, STOP_LENGTH = 1, STOP_ABORTED = 2, STOP_SINK = 3;
const int ERR_PROMPT_TOO_LONG = -1, ERR_DECODE = -2, ERR_GRAMMAR = -3, ERR_BUSY = -4, ERR_EMPTY = -5;

} // namespace

extern "C" {

JNIEXPORT void JNICALL
Java_com_livingai_core_ai_LlamaNative_setVerbose(JNIEnv *, jobject, jboolean verbose) { quiet.store(!verbose); }

JNIEXPORT jlong JNICALL
Java_com_livingai_core_ai_LlamaNative_load(JNIEnv *env, jobject, jstring jpath, jint nCtx, jint nThreads, jint nBatch, jboolean useMmap) {
    std::call_once(backendOnce, [] {
        llama_log_set(logCallback, nullptr);
        llama_backend_init();
    });
    const char *path = env->GetStringUTFChars(jpath, nullptr);
    llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = 0;
    mp.use_mmap = useMmap;
    llama_model *model = llama_model_load_from_file(path, mp);
    env->ReleaseStringUTFChars(jpath, path);
    if (!model) return 0;

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = (uint32_t) nCtx;
    cp.n_batch = (uint32_t) nBatch;
    cp.n_threads = nThreads;
    cp.n_threads_batch = nThreads;
    cp.no_perf = true;
    llama_context *ctx = llama_init_from_model(model, cp);
    if (!ctx) { llama_model_free(model); return 0; }

    auto *s = new Session();
    s->model = model; s->ctx = ctx; s->vocab = llama_model_get_vocab(model);
    llama_set_abort_callback(ctx, [](void *data) { return static_cast<Session *>(data)->abort.load(); }, s);
    return reinterpret_cast<jlong>(s);
}

JNIEXPORT void JNICALL
Java_com_livingai_core_ai_LlamaNative_free(JNIEnv *, jobject, jlong handle) {
    auto *s = reinterpret_cast<Session *>(handle);
    if (!s) return;
    s->abort.store(true);
    { std::lock_guard<std::mutex> guard(s->lock); }
    llama_free(s->ctx);
    llama_model_free(s->model);
    delete s;
}

JNIEXPORT void JNICALL
Java_com_livingai_core_ai_LlamaNative_abort(JNIEnv *, jobject, jlong handle) {
    auto *s = reinterpret_cast<Session *>(handle);
    if (s) s->abort.store(true);
}

// "description\nparameters\nbytes\ncontext\nvocabulary"
JNIEXPORT jstring JNICALL
Java_com_livingai_core_ai_LlamaNative_info(JNIEnv *env, jobject, jlong handle) {
    auto *s = reinterpret_cast<Session *>(handle);
    if (!s) return env->NewStringUTF("");
    char desc[256] = {0};
    llama_model_desc(s->model, desc, sizeof(desc));
    std::string out = std::string(desc) + "\n" + std::to_string(llama_model_n_params(s->model)) + "\n" + std::to_string(llama_model_size(s->model)) +
                      "\n" + std::to_string(llama_n_ctx(s->ctx)) + "\n" + std::to_string(llama_vocab_n_tokens(s->vocab));
    return env->NewStringUTF(out.c_str());
}

// {promptTokens, reusedTokens, outputTokens, promptMs, generationMs}
JNIEXPORT jdoubleArray JNICALL
Java_com_livingai_core_ai_LlamaNative_stats(JNIEnv *env, jobject, jlong handle) {
    auto *s = reinterpret_cast<Session *>(handle);
    jdouble v[5] = {0, 0, 0, 0, 0};
    if (s) { v[0] = s->promptTokens; v[1] = s->reusedTokens; v[2] = s->outTokens; v[3] = s->promptMs; v[4] = s->genMs; }
    jdoubleArray out = env->NewDoubleArray(5);
    env->SetDoubleArrayRegion(out, 0, 5, v);
    return out;
}

JNIEXPORT jint JNICALL
Java_com_livingai_core_ai_LlamaNative_countTokens(JNIEnv *env, jobject, jlong handle, jbyteArray jtext) {
    auto *s = reinterpret_cast<Session *>(handle);
    if (!s) return 0;
    return (jint) tokenize(s->vocab, bytesToString(env, jtext), false, true).size();
}

// Formats a conversation with the chat template stored in the model file. Returns null if the model has none.
JNIEXPORT jbyteArray JNICALL
Java_com_livingai_core_ai_LlamaNative_applyTemplate(JNIEnv *env, jobject, jlong handle, jobjectArray jroles, jobjectArray jcontents, jboolean addAssistant) {
    auto *s = reinterpret_cast<Session *>(handle);
    if (!s) return nullptr;
    const char *tmpl = llama_model_chat_template(s->model, nullptr);
    if (!tmpl) return nullptr;
    jsize n = env->GetArrayLength(jroles);
    std::vector<std::string> roles((size_t) n), contents((size_t) n);
    std::vector<llama_chat_message> messages((size_t) n);
    size_t total = 256;
    for (jsize i = 0; i < n; i++) {
        auto jr = (jbyteArray) env->GetObjectArrayElement(jroles, i);
        auto jc = (jbyteArray) env->GetObjectArrayElement(jcontents, i);
        roles[(size_t) i] = bytesToString(env, jr);
        contents[(size_t) i] = bytesToString(env, jc);
        env->DeleteLocalRef(jr); env->DeleteLocalRef(jc);
        messages[(size_t) i] = {roles[(size_t) i].c_str(), contents[(size_t) i].c_str()};
        total += roles[(size_t) i].size() + contents[(size_t) i].size() + 64;
    }
    std::string buf(total * 2, '\0');
    int32_t len = llama_chat_apply_template(tmpl, messages.data(), messages.size(), addAssistant, &buf[0], (int32_t) buf.size());
    if (len > (int32_t) buf.size()) {
        buf.resize((size_t) len + 1);
        len = llama_chat_apply_template(tmpl, messages.data(), messages.size(), addAssistant, &buf[0], (int32_t) buf.size());
    }
    if (len < 0) return nullptr;
    buf.resize((size_t) len);
    return stringToBytes(env, buf);
}

// Generates text after `prompt`. Each piece goes to sink.onPiece(byte[]) which returns false to stop.
// Returns a STOP_* reason (>= 0) or an ERR_* code (< 0).
JNIEXPORT jint JNICALL
Java_com_livingai_core_ai_LlamaNative_generate(JNIEnv *env, jobject, jlong handle, jbyteArray jprompt, jint maxTokens, jfloat temperature, jfloat topP,
                                               jint topK, jfloat repeatPenalty, jbyteArray jgrammar, jint seed, jobject sink) {
    auto *s = reinterpret_cast<Session *>(handle);
    if (!s) return ERR_EMPTY;
    std::unique_lock<std::mutex> guard(s->lock, std::try_to_lock);
    if (!guard.owns_lock()) return ERR_BUSY;
    s->abort.store(false);
    s->promptTokens = s->reusedTokens = s->outTokens = 0; s->promptMs = s->genMs = 0;

    jclass sinkClass = env->GetObjectClass(sink);
    jmethodID onPiece = env->GetMethodID(sinkClass, "onPiece", "([B)Z");

    std::vector<llama_token> prompt = tokenize(s->vocab, bytesToString(env, jprompt), true, true);
    if (prompt.empty()) return ERR_EMPTY;
    const int nCtx = (int) llama_n_ctx(s->ctx);
    const int nBatch = (int) llama_n_batch(s->ctx);
    if ((int) prompt.size() + 8 >= nCtx) return ERR_PROMPT_TOO_LONG;
    if ((int) prompt.size() + maxTokens > nCtx) maxTokens = nCtx - (int) prompt.size();

    // reuse the part of the context that is identical; always re-evaluate at least the last token to get fresh logits
    size_t common = 0;
    while (common < s->cached.size() && common < prompt.size() - 1 && s->cached[common] == prompt[common]) common++;
    llama_memory_t mem = llama_get_memory(s->ctx);
    if (common < s->cached.size()) {
        if (!llama_memory_seq_rm(mem, 0, (llama_pos) common, -1)) { llama_memory_clear(mem, true); common = 0; }
        s->cached.resize(common);
    }
    s->promptTokens = (int) prompt.size(); s->reusedTokens = (int) common;

    double t0 = nowMs();
    for (size_t i = common; i < prompt.size();) {
        int n = (int) std::min((size_t) nBatch, prompt.size() - i);
        if (llama_decode(s->ctx, llama_batch_get_one(prompt.data() + i, n)) != 0) {
            llama_memory_clear(mem, true); s->cached.clear();
            return s->abort.load() ? STOP_ABORTED : ERR_DECODE;
        }
        s->cached.insert(s->cached.end(), prompt.begin() + (long) i, prompt.begin() + (long) i + n);
        i += (size_t) n;
    }
    s->promptMs = nowMs() - t0;

    // sampling: penalties → top-k → top-p → temperature → random pick (or greedy when temperature is 0)
    llama_sampler *chain = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (repeatPenalty > 1.0f) llama_sampler_chain_add(chain, llama_sampler_init_penalties(64, repeatPenalty, 0.0f, 0.0f));
    if (temperature <= 0.0f) {
        llama_sampler_chain_add(chain, llama_sampler_init_greedy());
    } else {
        if (topK > 0) llama_sampler_chain_add(chain, llama_sampler_init_top_k(topK));
        if (topP < 1.0f) llama_sampler_chain_add(chain, llama_sampler_init_top_p(topP, 1));
        llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(chain, llama_sampler_init_dist(seed < 0 ? LLAMA_DEFAULT_SEED : (uint32_t) seed));
    }
    for (llama_token t : prompt) llama_sampler_accept(chain, t);

    llama_sampler *grammar = nullptr;
    std::string grammarText = bytesToString(env, jgrammar);
    if (!grammarText.empty()) {
        grammar = llama_sampler_init_grammar(s->vocab, grammarText.c_str(), "root");
        if (!grammar) { llama_sampler_free(chain); return ERR_GRAMMAR; }
    }

    const int nVocab = llama_vocab_n_tokens(s->vocab);
    std::vector<llama_token_data> candidates((size_t) nVocab);
    auto fill = [&](const float *logits) {
        candidates.resize((size_t) nVocab);
        for (int i = 0; i < nVocab; i++) candidates[(size_t) i] = llama_token_data{i, logits[i], 0.0f};
    };

    int result = STOP_LENGTH;
    double t1 = nowMs();
    for (int produced = 0; produced < maxTokens; produced++) {
        if (s->abort.load()) { result = STOP_ABORTED; break; }
        const float *logits = llama_get_logits_ith(s->ctx, -1);
        fill(logits);
        llama_token_data_array arr = {candidates.data(), candidates.size(), -1, false};
        llama_sampler_apply(chain, &arr);
        llama_token token = arr.data[arr.selected].id;
        if (grammar) {
            // cheap check of the one picked token first; only when the grammar rejects it is the whole vocabulary filtered
            llama_token_data single = {token, 1.0f, 0.0f};
            llama_token_data_array one = {&single, 1, -1, false};
            llama_sampler_apply(grammar, &one);
            if (std::isinf(single.logit) && single.logit < 0) {
                fill(logits);
                arr = {candidates.data(), candidates.size(), -1, false};
                llama_sampler_apply(grammar, &arr);
                llama_sampler_apply(chain, &arr);
                token = arr.data[arr.selected].id;
            }
            llama_sampler_accept(grammar, token);
        }
        llama_sampler_accept(chain, token);

        if (llama_vocab_is_eog(s->vocab, token)) { result = STOP_EOS; break; }
        s->outTokens++;
        std::string text = piece(s->vocab, token);
        jbyteArray bytes = stringToBytes(env, text);
        jboolean more = env->CallBooleanMethod(sink, onPiece, bytes);
        env->DeleteLocalRef(bytes);
        if (env->ExceptionCheck()) { result = STOP_SINK; break; }

        if (llama_decode(s->ctx, llama_batch_get_one(&token, 1)) != 0) {
            result = s->abort.load() ? STOP_ABORTED : ERR_DECODE;
            llama_memory_clear(mem, true); s->cached.clear();
            break;
        }
        s->cached.push_back(token);
        if (!more) { result = STOP_SINK; break; }
        if ((int) s->cached.size() + 1 >= nCtx) { result = STOP_LENGTH; break; }
    }
    s->genMs = nowMs() - t1;
    if (grammar) llama_sampler_free(grammar);
    llama_sampler_free(chain);
    return result;
}

} // extern "C"
