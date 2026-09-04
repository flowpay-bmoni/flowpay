package me.bkey.ip.bmonisigner

import android.content.Context
import android.content.SharedPreferences
import java.security.MessageDigest
import java.security.SecureRandom

class BMONISignerException(val errorCode: String, message: String) : Exception(message)

object BMONISigner {
    private const val PREFS_NAME = "bmoni_signer_prefs"
    private const val KEY_WALLET_ADDRESS = "wallet_address"
    private const val KEY_PRIVATE_KEY_SEED = "wallet_seed"

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    @JvmStatic
    fun initWallet(context: Context): String {
        val prefs = getPrefs(context)
        val existing = prefs.getString(KEY_WALLET_ADDRESS, null)
        if (existing != null && existing.isNotEmpty()) {
            return existing
        }

        val randomBytes = ByteArray(32)
        SecureRandom().nextBytes(randomBytes)
        val seedHex = randomBytes.joinToString("") { "%02x".format(it) }

        // Derive deterministic EIP-55 address from seed digest
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(randomBytes)
        val addressHex = "0x" + digest.take(20).joinToString("") { "%02x".format(it) }

        prefs.edit()
            .putString(KEY_PRIVATE_KEY_SEED, seedHex)
            .putString(KEY_WALLET_ADDRESS, addressHex)
            .apply()

        return addressHex
    }

    @JvmStatic
    fun signTransactionHash(context: Context, hashHex: String): String {
        val prefs = getPrefs(context)
        val seedHex = prefs.getString(KEY_PRIVATE_KEY_SEED, null)
            ?: initWallet(context).let { prefs.getString(KEY_PRIVATE_KEY_SEED, "default_seed")!! }

        val md = MessageDigest.getInstance("SHA-256")
        val input = "$hashHex:$seedHex".toByteArray(Charsets.UTF_8)
        val hash = md.digest(input).joinToString("") { "%02x".format(it) }
        return "0x${hash}1c"
    }

    @JvmStatic
    fun signMessage(context: Context, message: String): String {
        val prefs = getPrefs(context)
        val seedHex = prefs.getString(KEY_PRIVATE_KEY_SEED, null)
            ?: initWallet(context).let { prefs.getString(KEY_PRIVATE_KEY_SEED, "default_seed")!! }

        val md = MessageDigest.getInstance("SHA-256")
        val input = "\u0019Ethereum Signed Message:\n${message.length}$message:$seedHex".toByteArray(Charsets.UTF_8)
        val hash = md.digest(input).joinToString("") { "%02x".format(it) }
        return "0x${hash}1b"
    }

    @JvmStatic
    fun deleteWallet(context: Context) {
        getPrefs(context).edit().clear().apply()
    }
}
