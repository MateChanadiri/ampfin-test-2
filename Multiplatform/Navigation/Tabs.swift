//
//  NavigationRoot.swift
//  Music
//
//  Created by Rasmus Krämer on 06.09.23.
//

import SwiftUI
import Defaults
import AmpFinKit
import AFPlayback

internal struct Tabs: View {
    @Default(.activeTab) private var activeTab
    @Default(.searchTab) private var searchTab
    
    @State private var search: String = ""
    @State private var searchSelected = false
    
    @State private var homePath = NavigationPath()
    @State private var newPath = NavigationPath()
    @State private var radioPath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    
    private var selection: Binding<Selection> {
        .init(get: { activeTab }, set: {
            if activeTab == $0 {
                switch activeTab {
                    case .home:
                        homePath = NavigationPath()
                    case .new:
                        newPath = NavigationPath()
                    case .radio:
                        radioPath = NavigationPath()
                    case .library:
                        libraryPath = NavigationPath()
                    case .search:
                        search = ""
                        searchSelected = true
                        searchPath = NavigationPath()
                }
            }
            
            activeTab = $0
        })
    }
    
    private func feed(_ feed: ModuleHost.Feed, title: LocalizedStringKey, path: Binding<NavigationPath>) -> some View {
        NavigationStack(path: path) {
            FeedView(feed: feed, title: title)
                .modifier(Navigation.DestinationModifier())
        }
        .environment(\.libraryDataProvider, OnlineLibraryDataProvider())
        .onReceive(NotificationCenter.default.publisher(for: Navigation.navigateNotification)) { notification in
            append(notification, to: path)
        }
    }
    
    private func append(_ notification: Notification, to path: Binding<NavigationPath>) {
        if let albumId = notification.userInfo?["albumId"] as? String {
            path.wrappedValue.append(Navigation.AlbumLoadDestination(albumId: albumId))
        } else if let artistId = notification.userInfo?["artistId"] as? String {
            path.wrappedValue.append(Navigation.ArtistLoadDestination(artistId: artistId))
        } else if let playlistId = notification.userInfo?["playlistId"] as? String {
            path.wrappedValue.append(Navigation.PlaylistLoadDestination(playlistId: playlistId))
        }
    }
    
    private var tabs: some View {
        TabView(selection: selection) {
            Tab("tab.home", systemImage: "house.fill", value: Selection.home) {
                feed(.home, title: "tab.home", path: $homePath)
            }
            
            Tab("tab.new", systemImage: "square.grid.2x2.fill", value: Selection.new) {
                feed(.new, title: "tab.new", path: $newPath)
            }
            
            Tab("tab.radio", systemImage: "dot.radiowaves.left.and.right", value: Selection.radio) {
                feed(.radio, title: "tab.radio", path: $radioPath)
            }
            
            Tab("tab.library", systemImage: "play.square.stack.fill", value: Selection.library) {
                NavigationStack(path: $libraryPath) {
                    LibraryView()
                        .modifier(Navigation.DestinationModifier())
                }
                .environment(\.libraryDataProvider, OnlineLibraryDataProvider())
                .onReceive(NotificationCenter.default.publisher(for: Navigation.navigateNotification)) { notification in
                    append(notification, to: $libraryPath)
                }
            }
            
            Tab(value: Selection.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView(search: $search, searchTab: $searchTab, selected: $searchSelected)
                        .modifier(Navigation.DestinationModifier())
                }
                .environment(\.libraryDataProvider, searchTab.dataProvider)
            } label: {
                Label("tab.search", systemImage: "magnifyingglass")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .modifier(NowPlaying.CompactTabBarBackgroundModifier())
    }
    
    var body: some View {
        tabs
            .modifier(NowPlaying.CompactModifier())
            .modifier(Navigation.NotificationModifier(
                navigateAlbum: {
                    activeTab = .library
                    
                    NotificationCenter.default.post(name: Navigation.navigateNotification, object: nil, userInfo: [
                        "albumId": $0
                    ])
                }, navigateArtist: {
                    activeTab = .library
                    
                    NotificationCenter.default.post(name: Navigation.navigateNotification, object: nil, userInfo: [
                        "artistId": $0,
                    ])
                }, navigatePlaylist: {
                    activeTab = .library
                    
                    NotificationCenter.default.post(name: Navigation.navigateNotification, object: nil, userInfo: [
                        "playlistId": $0
                    ])
                }))
    }
}

internal extension Tabs {
    enum Selection: Int, Defaults.Serializable {
        case home = 0
        case new = 1
        case radio = 2
        case library = 3
        case search = 4
    }
}

// MARK: Home / New / Radio

/// Shelves supplied by the installed modules.
internal struct FeedView: View {
    let feed: ModuleHost.Feed
    let title: LocalizedStringKey
    
    private let host = ModuleHost.shared
    
    @State private var shelves = [SourceShelf]()
    @State private var loading = false
    @State private var loaded = false
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(shelves) {
                    ShelfView(shelf: $0)
                }
            }
            .padding(.vertical, 12)
        }
        .overlay {
            if host.modules.isEmpty {
                ContentUnavailableView {
                    Label("modules.empty", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("modules.empty.description")
                } actions: {
                    AddModuleButton()
                        .buttonStyle(.borderedProminent)
                }
            } else if loading && shelves.isEmpty {
                ProgressView()
            } else if loaded && shelves.isEmpty {
                ContentUnavailableView("modules.nothing", systemImage: "music.note", description: Text("modules.nothing.description"))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .modifier(NowPlaying.SafeAreaModifier())
        .modifier(AccountToolbarButtonModifier(requiredSize: nil))
        .animation(.smooth, value: shelves.count)
        .refreshable {
            await load()
        }
        .task(id: host.modules.map(\.id)) {
            await load()
        }
    }
    
    private func load() async {
        guard !host.modules.isEmpty else {
            shelves = []
            return
        }
        
        loading = true
        let result = await SourceClient.shared.shelves(feed)
        
        guard !Task.isCancelled else {
            return
        }
        
        shelves = result
        loading = false
        loaded = true
    }
}

internal struct ShelfView: View {
    let shelf: SourceShelf
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shelf.title)
                .font(.title2.bold())
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(shelf.tracks.enumerated()), id: \.offset) { index, track in
                        Button {
                            AudioPlayer.current.startPlayback(tracks: shelf.tracks, startIndex: index, shuffle: false, playbackInfo: .init(container: nil))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ItemImage(cover: track.cover, cornerRadius: 14)
                                    .frame(width: 156, height: 156)
                                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                                
                                Text(track.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                
                                if let artistName = track.artistName {
                                    Text(artistName)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 156, alignment: .leading)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .modifier(NowPlaying.ContextMenuModifier(track: track))
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

internal struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

internal extension View {
    /// Liquid Glass on iOS 26, frosted material before that.
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

#Preview {
    Tabs()
}
