package de.letzgo.stashy.data

import androidx.core.content.FileProvider

/** Own subclass so the self-update provider (sideload manifest) doesn't clash with other FileProviders. */
class UpdateFileProvider : FileProvider()
