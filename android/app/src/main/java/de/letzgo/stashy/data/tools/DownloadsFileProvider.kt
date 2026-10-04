package de.letzgo.stashy.data.tools

import androidx.core.content.FileProvider

/** Own subclass for sharing downloads — two providers with the same class name break the manifest merge. */
class DownloadsFileProvider : FileProvider()
