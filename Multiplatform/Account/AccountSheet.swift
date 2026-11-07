//
//  AccountSheet.swift
//  Music
//
//  Created by Rasmus Krämer on 06.09.23.
//

import SwiftUI
import TipKit
import Nuke
import UniformTypeIdentifiers
import AmpFinKit

/// The file chooser: pick one or more .js modules.
internal struct AddModuleButton: View {
    private let host = ModuleHost.shared
    
    @State private var picking = false
    @State private var message: String?
    
    var body: some View {
        Button {
            picking = true
        } label: {
            Label("modules.add", systemImage: "puzzlepiece.extension.fill")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.javaScript, .plainText, .text], allowsMultipleSelection: true) { result in
            switch result {
                case .success(let urls):
                    for url in urls {
                        do {
                            try host.add(from: url)
                        } catch {
                            message = "\(url.lastPathComponent): \(error.localizedDescription)"
                        }
                    }
                case .failure(let error):
                    message = error.localizedDescription
            }
        }
        .alert("modules.add.failed", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("done", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

internal struct AccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    private let host = ModuleHost.shared
    
    @State private var downloads: [Track]? = nil
    
    var body: some View {
        NavigationStack {
            List {
                Section("modules") {
                    ForEach(host.modules) { module in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.name)
                            
                            if let error = host.runErrors[module.id] {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else {
                                Text(module.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { host.modules[$0] }.forEach { host.remove($0) }
                    }
                    
                    ForEach(host.loadErrors, id: \.self) { error in
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    AddModuleButton()
                }
                
                Section {
                    Button {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    } label: {
                        Label("account.settings", systemImage: "gear")
                    }
                }
                .foregroundStyle(.primary)
                
                Section("account.downloads.queue") {
                    if let downloads = downloads {
                        if downloads.isEmpty {
                            Text("account.downloads.queue.empty")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(downloads) {
                                TrackListRow(track: $0, preview: true) {}
                            }
                        }
                    } else {
                        ProgressView()
                            .onAppear {
                                downloads = try? OfflineManager.shared.downloading()
                            }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        SpotlightHelper.deleteSpotlightIndex()
                        ImagePipeline.shared.cache.removeAll()
                    } label: {
                        Label("account.deleteSpotlightIndex", systemImage: "square.stack.3d.up.slash")
                    }
                    
                    Button(role: .destructive) {
                        try! OfflineManager.shared.delete()
                    } label: {
                        Label("account.deleteDownloads", systemImage: "slash.circle")
                    }
                }
                .foregroundStyle(.red)
                
                Section("account.app") {
                    Text("account.version.app \(SourceClient.shared.clientVersion) \(SourceClient.shared.clientBuild)")
                    Text("account.version.database \(PersistenceManager.shared.modelContainer.schema.version.description) \(PersistenceManager.shared.modelContainer.configurations.map { $0.name }.joined(separator: ", "))")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("account.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("done")
                    }
                }
            }
        }
    }
}

internal struct AccountToolbarButtonModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var accountSheetPresented = false
    
    let requiredSize: UserInterfaceSizeClass?
    
    func body(content: Content) -> some View {
        if requiredSize == nil || horizontalSizeClass == requiredSize {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            accountSheetPresented.toggle()
                        } label: {
                            Label("account", systemImage: "person.crop.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .sheet(isPresented: $accountSheetPresented) {
                    AccountSheet()
                }
        } else {
            content
        }
    }
}


#Preview {
    Text(verbatim: ":)")
        .sheet(isPresented: .constant(true)) {
            AccountSheet()
        }
}
