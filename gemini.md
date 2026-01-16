# Stashy Project Overview

## Introduction
Stashy is a SwiftUI-based application designed for iOS and macOS that serves as a client for a StashDB server. It allows users to browse and interact with their Stash library, including scenes, performers, and studios.

## Architecture
The project follows the **MVVM (Model-View-ViewModel)** pattern, leveraging **SwiftUI** for the user interface and **Combine** for reactive data handling.

### Directory Structure
```
stashy/
├── Networking/              # NEW: Network layer
│   └── GraphQLClient.swift  # Centralized GraphQL API client
├── Repositories/            # PLANNED: Data access layer
├── ViewModels/              # PLANNED: Domain-specific ViewModels
├── Views/                   # SwiftUI views
├── Managers/                # Singleton managers
│   ├── ServerConfigManager  # Multi-server configuration
│   ├── ImageCacheManager    # Memory + Disk image cache
│   ├── TabManager           # UI configuration
│   └── DownloadManager      # Offline downloads
└── Utilities/              
    └── SharedUtilities.swift
```

### Key Components

#### `Networking/GraphQLClient.swift` (NEW)
Centralized GraphQL client providing:
- **Async/Await API**: Modern Swift concurrency
- **Combine API**: For reactive data flows
- **Completion Handler API**: For backward compatibility
- **Error Handling**: Typed NetworkError enum

#### `StashDBViewModel.swift`
Legacy view model (being refactored) responsible for:
- **Data Management**: fetching and storing lists of Scenes, Performers, and Studios.
- **State Management**: handling loading states, error messages, and pagination.

#### `ImageCacheManager.swift`
Dual-layer image caching:
- **Memory Cache**: NSCache with 200MB limit
- **Disk Cache**: SHA256-hashed files with 7-day expiration

#### `ServerConfigManager.swift`
Multi-server configuration manager:
- **Multi-Server Support**: Switch between servers
- **Persistent Storage**: UserDefaults
- **Migration Logic**: Backward compatibility

### Data Models
- `Scene`: Represents a video scene
- `Performer`: Represents an actor/performer  
- `Studio`: Represents a production studio
- `Gallery`: Image gallery
- `Tag`: Content tags

## Technology Stack
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Reactive Framework**: Combine
- **Concurrency**: Swift async/await
- **API**: GraphQL (queries in `/graphql/*.graphql`)

## Architecture Improvement Plan
See `.agent/workflows/architecture-improvement.md` for the 6-phase improvement plan:
1. Network Layer Extraction ✅ (In Progress)
2. Query Externalization
3. Repository Pattern
4. Pagination Abstraction
5. ViewModel Decomposition
6. API Caching

## Setup & Configuration
The app requires a connection to a running StashDB server. Configuration (URL, API Key) is handled via `ServerConfigManager`.
