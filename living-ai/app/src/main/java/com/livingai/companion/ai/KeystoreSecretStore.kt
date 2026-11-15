package com.livingai.companion.ai

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.livingai.core.ai.SecretStore
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * API keys encrypted with an AES-256-GCM key that lives in the Android Keystore (it never leaves
 * the secure hardware and cannot be exported). Only the ciphertext is written to preferences.
 */
class KeystoreSecretStore(context: Context) : SecretStore {
    private val sp = context.applicationContext.getSharedPreferences("kivo_secrets", Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build()
        )
        return gen.generateKey()
    }

    override fun get(id: String): String = try {
        val raw = sp.getString(id, null) ?: return ""
        val bytes = Base64.decode(raw, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, 12))
        String(cipher.doFinal(bytes, 12, bytes.size - 12), Charsets.UTF_8)
    } catch (e: Exception) { "" }

    override fun put(id: String, secret: String) {
        if (secret.isBlank()) { remove(id); return }
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val out = cipher.iv + cipher.doFinal(secret.toByteArray(Charsets.UTF_8))
            sp.edit().putString(id, Base64.encodeToString(out, Base64.NO_WRAP)).apply()
        } catch (e: Exception) { /* without a working keystore the key is simply not stored */ }
    }

    override fun remove(id: String) { sp.edit().remove(id).apply() }

    fun clear() { sp.edit().clear().apply() }

    private companion object { const val ALIAS = "kivo_api_keys" }
}
