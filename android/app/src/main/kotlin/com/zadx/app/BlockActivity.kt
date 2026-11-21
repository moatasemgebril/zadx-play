package com.zadx.app

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Full-screen shield shown over a locked app, the Settings app (child) or the uninstall dialog. */
class BlockActivity : Activity() {

    companion object {
        const val EXTRA_REASON = "reason"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val arabic = resources.configuration.locales[0].language == "ar"
        val reason = intent.getStringExtra(EXTRA_REASON) ?: "requiredTasks"
        val allApps = LockStore.mode(this) == LockRules.MODE_ALL_APPS

        val message = when (reason) {
            // Device protection (docs/decisions/DEVICE-PROTECTION.md).
            "settings" -> if (arabic) "الإعدادات لبابا وماما بس\nاطلب منهم يفتحوها من Zad X" else "Settings are for parents\nAsk your parent to open them in Zad X"
            "uninstall" -> if (arabic) "مسح التطبيقات محتاج بابا أو ماما\nاطلب منهم من Zad X" else "Deleting apps needs a parent\nAsk your parent in Zad X"
            // Free plan: the prayer lock ends by itself after a short window.
            "prayer" -> if (LockStore.prayerAutoEndMinutes(this) > 0) {
                if (arabic) "التطبيقات مقفولة وقت الصلاة، وهتفتح بعد شوية" else "Apps are locked for prayer time — they open again soon"
            } else when {
                allApps && arabic -> "وقت الصلاة\nالتطبيقات مقفولة لحد ما تصلي"
                allApps -> "Prayer time\nApps are locked until you pray"
                arabic -> "وقت الصلاة\nالألعاب مقفولة لحد ما تصلي"
                else -> "Prayer time\nGames are locked until you pray"
            }
            "noTime" -> if (arabic) "خلص وقتك النهارده\nاعمل مهمة تكسب وقت" else "Out of time today\nDo a task to earn more"
            else -> when {
                allApps && arabic -> "خلّص مهامك الأول\nوبعدها التطبيق يتفتح"
                allApps -> "Finish your tasks first\nthen the app unlocks"
                arabic -> "خلّص مهامك الأول\nوبعدها اللعبة تتفتح"
                else -> "Finish your tasks first\nthen the game unlocks"
            }
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0A225E"))
            setPadding(dp(32), dp(32), dp(32), dp(32))
        }
        root.addView(TextView(this).apply {
            text = "Zad X"
            setTextColor(Color.parseColor("#FFC83D"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 40f)
            gravity = Gravity.CENTER
        })
        root.addView(TextView(this).apply {
            text = message
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            gravity = Gravity.CENTER
            setPadding(0, dp(24), 0, dp(32))
        })
        root.addView(Button(this).apply {
            text = if (arabic) "افتح Zad X" else "Open Zad X"
            setTextColor(Color.parseColor("#1F1A3D"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(Color.parseColor("#FFC83D"))
            }
            minHeight = dp(56)
            setOnClickListener {
                startActivity(
                    Intent(this@BlockActivity, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                )
                finish()
            }
        })
        setContentView(root)
    }

    /** Back goes to the home screen, never back into the locked game. */
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
}
