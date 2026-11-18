package app.thinkcaps.android

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

internal class WordDatabase(context: Context) :
    SQLiteOpenHelper(context, "thinkcaps.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE words (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                english TEXT NOT NULL,
                russian TEXT NOT NULL,
                context TEXT NOT NULL,
                automatic INTEGER NOT NULL,
                enDue INTEGER NOT NULL,
                enStreak INTEGER NOT NULL DEFAULT 0,
                enDays INTEGER NOT NULL DEFAULT 0,
                ruDue INTEGER NOT NULL,
                ruStreak INTEGER NOT NULL DEFAULT 0,
                ruDays INTEGER NOT NULL DEFAULT 0,
                UNIQUE (english COLLATE NOCASE, russian COLLATE NOCASE, context)
            )
        """.trimIndent())
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun entries(): List<Map<String, Any>> =
        readableDatabase.query("words", null, null, null, null, null, "id DESC").use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(buildMap {
                        for (name in listOf("id", "enDue", "enStreak", "enDays", "ruDue", "ruStreak", "ruDays")) {
                            put(name, cursor.getLong(cursor.getColumnIndexOrThrow(name)))
                        }
                        for (name in listOf("english", "russian", "context")) {
                            put(name, cursor.getString(cursor.getColumnIndexOrThrow(name)))
                        }
                        put("automatic", cursor.getInt(cursor.getColumnIndexOrThrow("automatic")) != 0)
                    })
                }
            }
        }

    fun save(args: Map<*, *>) {
        val id = (args["id"] as? Number)?.toLong()
        val values = ContentValues().apply {
            for (name in listOf("english", "russian", "context")) put(name, args[name] as String)
            put("automatic", args["automatic"] as Boolean)
        }
        if (id == null) {
            val now = (args["now"] as Number).toLong()
            values.put("enDue", now)
            values.put("ruDue", now)
            writableDatabase.insertOrThrow("words", null, values)
        } else {
            check(writableDatabase.update("words", values, "id = ?", arrayOf(id.toString())) == 1)
        }
    }

    fun remove(id: Number) {
        writableDatabase.delete("words", "id = ?", arrayOf(id.toString()))
    }

    fun grade(args: Map<*, *>) {
        val prefix = when (args["direction"]) {
            "enToRu" -> "en"
            "ruToEn" -> "ru"
            else -> error("Invalid review direction")
        }
        val values = ContentValues().apply {
            put("${prefix}Due", (args["due"] as Number).toLong())
            put("${prefix}Streak", (args["streak"] as Number).toInt())
            put("${prefix}Days", (args["days"] as Number).toInt())
        }
        check(writableDatabase.update("words", values, "id = ?", arrayOf(args["id"].toString())) == 1)
    }
}
