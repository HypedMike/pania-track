// Just enough of android.content for the pure-logic classes to compile on a plain JVM. Test-only.
package android.content
import java.io.File
interface SharedPreferences {
    interface Editor { fun putString(k: String, v: String?): Editor; fun remove(k: String): Editor; fun apply() }
    fun getString(k: String, d: String?): String?
    fun edit(): Editor
}
abstract class Context {
    abstract fun getSharedPreferences(name: String, mode: Int): SharedPreferences
    abstract val filesDir: File
    companion object { const val MODE_PRIVATE = 0 }
}
