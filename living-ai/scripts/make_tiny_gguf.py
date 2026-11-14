#!/usr/bin/env python3
"""Writes a tiny GGUF language model with RANDOM weights and the real Qwen2 tokenizer.

It cannot say anything meaningful. It exists so the native engine (loading, tokenising Thai,
chat template, sampling, grammar, cache reuse, abort) can be tested in seconds on any machine,
without downloading a real model.

usage: make_tiny_gguf.py <llama.cpp checkout> <output.gguf>
"""
import sys
import numpy as np

llama_dir, out_path = sys.argv[1], sys.argv[2]
sys.path.insert(0, llama_dir + "/gguf-py")
import gguf  # noqa: E402

reader = gguf.GGUFReader(llama_dir + "/models/ggml-vocab-qwen2.gguf")
n_vocab = len(reader.fields["tokenizer.ggml.tokens"].data)
dim, layers, heads, ff, ctx = 48, 2, 4, 96, 2048

w = gguf.GGUFWriter(out_path, "llama")
w.add_name("kivo-tiny-random")
w.add_context_length(ctx)
w.add_embedding_length(dim)
w.add_block_count(layers)
w.add_feed_forward_length(ff)
w.add_head_count(heads)
w.add_head_count_kv(heads)
w.add_layer_norm_rms_eps(1e-5)
w.add_rope_dimension_count(dim // heads)
w.add_file_type(gguf.LlamaFileType.ALL_F32)
for name, field in reader.fields.items():
    if not name.startswith("tokenizer."):
        continue
    sub = field.types[-1] if field.types[0] == gguf.GGUFValueType.ARRAY else None
    w.add_key_value(name, field.contents(), field.types[0], sub_type=sub)
w.add_chat_template(
    "{% for message in messages %}{{'<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>' + '\n'}}{% endfor %}"
    "{% if add_generation_prompt %}{{ '<|im_start|>assistant\n' }}{% endif %}"
)

rng = np.random.default_rng(7)
def t(*shape, scale=0.05):
    return (rng.standard_normal(shape) * scale).astype(np.float32)

w.add_tensor("token_embd.weight", t(n_vocab, dim))
for i in range(layers):
    p = f"blk.{i}."
    w.add_tensor(p + "attn_norm.weight", np.ones(dim, dtype=np.float32))
    for n in ("attn_q", "attn_k", "attn_v", "attn_output"):
        w.add_tensor(p + n + ".weight", t(dim, dim))
    w.add_tensor(p + "ffn_norm.weight", np.ones(dim, dtype=np.float32))
    w.add_tensor(p + "ffn_gate.weight", t(ff, dim))
    w.add_tensor(p + "ffn_up.weight", t(ff, dim))
    w.add_tensor(p + "ffn_down.weight", t(dim, ff))
w.add_tensor("output_norm.weight", np.ones(dim, dtype=np.float32))
w.add_tensor("output.weight", t(n_vocab, dim, scale=0.3))

w.write_header_to_file()
w.write_kv_data_to_file()
w.write_tensors_to_file()
w.close()
print("wrote", out_path, "vocab", n_vocab)
