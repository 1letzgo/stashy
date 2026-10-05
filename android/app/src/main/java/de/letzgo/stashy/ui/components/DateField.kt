package de.letzgo.stashy.ui.components

import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import de.letzgo.stashy.ui.NativeTextField
import de.letzgo.stashy.ui.SF
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle

/**
 * Stash's `YYYY-MM-DD` date format — shared by the date criteria and every date field of the
 * edit sheets, so nothing that is not a real calendar date reaches the server
 * (iOS: `StashDateInput`).
 */
object StashDateInput {
    const val ERROR_TEXT = "Enter a valid date as YYYY-MM-DD"

    private val formatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("uuuu-MM-dd").withResolverStyle(ResolverStyle.STRICT)
    private val shape = Regex("""^\d{4}-\d{2}-\d{2}$""")

    /** A real calendar date in exactly `YYYY-MM-DD` (no 2023-02-30, no 2023-2-3). */
    fun parse(raw: String): LocalDate? {
        val t = raw.trim()
        if (!shape.matches(t)) return null
        return runCatching { LocalDate.parse(t, formatter) }.getOrNull()
    }

    fun isValid(raw: String): Boolean = parse(raw) != null

    /** Valid, or empty (the field is optional). */
    fun isAcceptable(raw: String): Boolean = raw.isBlank() || isValid(raw)

    fun format(date: LocalDate): String = date.format(formatter)
}

/**
 * `YYYY-MM-DD` Material text field with a calendar button (Material 3 [DatePickerDialog]) and an
 * inline error while the text is not a real date. Callers block their commit / Save on
 * [StashDateInput.isAcceptable]. [onCommit] fires on Done, focus loss and a pick in the dialog.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativeDateField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String?,
    modifier: Modifier = Modifier,
    placeholder: String? = "YYYY-MM-DD",
    onCommit: () -> Unit = {},
) {
    var showPicker by remember { mutableStateOf(false) }
    var focused by remember { mutableStateOf(false) }
    val invalid = !StashDateInput.isAcceptable(value)
    NativeTextField(
        value, onValueChange, label,
        modifier = modifier.onFocusChanged { if (focused && !it.isFocused) onCommit(); focused = it.isFocused },
        placeholder = placeholder,
        keyboard = KeyboardType.Ascii,
        imeAction = ImeAction.Done,
        keyboardActions = KeyboardActions(onDone = { onCommit() }),
        supportingText = if (invalid) StashDateInput.ERROR_TEXT else null,
        isError = invalid,
        trailing = {
            IconButton({ showPicker = true }) { Icon(SF.calendar, "Pick a date") }
        },
    )
    if (showPicker) {
        val initial = StashDateInput.parse(value) ?: LocalDate.now()
        val state = rememberDatePickerState(
            initialSelectedDateMillis = initial.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { showPicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        state.selectedDateMillis?.let { millis ->
                            onValueChange(StashDateInput.format(Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()))
                            onCommit()
                        }
                        showPicker = false
                    },
                    enabled = state.selectedDateMillis != null,
                ) { Text("OK") }
            },
            dismissButton = { TextButton({ showPicker = false }) { Text("Cancel") } },
        ) {
            DatePicker(state)
        }
    }
}
