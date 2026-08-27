import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudSyncCoordinator.self) private var cloudSync: CloudSyncCoordinator?
    @Bindable var playlist: Playlist

    @State var showDeleteConfirmation = false
    @State var showSync = false
    @State var showFullSync = false

    var isM3U: Bool {
        playlist.sourceType == .m3u
    }

    var isStalker: Bool {
        playlist.sourceType == .stalker
    }

    var connectionSectionTitle: LocalizedStringKey {
        switch playlist.sourceType {
        case .xtream: "Server"
        case .m3u: "M3U Playlist"
        case .stalker: "Stalker Portal"
        }
    }
    
    /// Field label for the primary URL, shared across the iOS/macOS and tvOS
    /// layouts — its wording depends on the playlist's source type.
    var serverURLFieldTitle: LocalizedStringKey {
        switch playlist.sourceType {
        case .xtream: "Server URL"
        case .m3u: "Playlist URL"
        case .stalker: "Portal URL"
        }
    }

    /// Explains the stream-format choice. m3u playlists carry their own URLs, so
    /// the wording there is about rewriting them rather than picking a default.
    var streamFormatFooter: LocalizedStringKey {
        isM3U
            ? "Automatic plays channels at the URL the playlist lists. Choose HLS or MPEG-TS to request that container instead; channels served through another kind of URL are unaffected."
            : "Automatic requests live channels as HLS. Choose MPEG-TS if channels stutter, refuse to start, or drop out — servers often serve one container more reliably than the other."
    }


    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            formBody
        #endif
    }

    #if !os(tvOS)
    private var formBody: some View {
        Form {
            editableSection

            if let status = playlist.userStatus {
                Section("Account") {
                    LabeledContent("Status", value: status)
                    if let expDate = playlist.expDate {
                        LabeledContent("Expires") {
                            Text(formattedExpiry(expDate))
                                .foregroundStyle(isExpired(expDate) ? .red : .secondary)
                        }
                    }
                    if let maxConn = playlist.maxConnections {
                        LabeledContent("Max Connections", value: maxConn)
                    }
                    if let activeConn = playlist.activeConnections {
                        LabeledContent("Active Connections", value: activeConn)
                    }
                }
            }

            if playlist.supportsStreamFormatChoice {
                streamFormatSection
            }

            syncSection

            Section {
                Button("Delete Playlist", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(playlist.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Delete Playlist", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deletePlaylist() }
        } message: {
            Text("All synced content for this playlist will also be removed.")
        }
        .sheet(isPresented: $showSync) {
            SyncProgressView(playlist: playlist)
        }
        .sheet(isPresented: $showFullSync) {
            SyncProgressView(playlist: playlist, full: true)
        }
    }
    #endif

    // MARK: - Editable Section (Always Editable)

    private var editableSection: some View {
        Section(connectionSectionTitle) {

            // Name
            TextField("Name", text: $playlist.name)
                .onChange(of: playlist.name) { _ in playlist.lastUpdated = Date() }

            // URL / Portal / Playlist
            TextField(serverURLFieldTitle, text: $playlist.serverURL)
                .autocorrectionDisabled()
                .textContentType(.URL)
                .onChange(of: playlist.serverURL) { _ in
                    playlist.lastUpdated = Date()
                    EPGSourceReconciler.reconcile(playlist, in: modelContext)
                }

            if isM3U {
                // EPG URL
                TextField("EPG URL (optional)", text: Binding(
                    get: { playlist.epgURL ?? "" },
                    set: { playlist.epgURL = $0.isEmpty ? nil : $0 }
                ))
                .autocorrectionDisabled()
                .textContentType(.URL)
                .onChange(of: playlist.epgURL) { _ in
                    playlist.lastUpdated = Date()
                    EPGSourceReconciler.reconcile(playlist, in: modelContext)
                }

            } else if isStalker {
                // MAC Address
                TextField("MAC Address", text: Binding(
                    get: { playlist.macAddress ?? "" },
                    set: { playlist.macAddress = $0.uppercased() }
                ))
                .autocorrectionDisabled()

                // Username
                TextField("Username (optional)", text: $playlist.username)
                    .autocorrectionDisabled()
                    .textContentType(.username)

                // Password
                SecureField("Password (optional)", text: $playlist.password)
                    .textContentType(.password)

            } else {
                // Xtream Username
                TextField("Username", text: $playlist.username)
                    .autocorrectionDisabled()
                    .textContentType(.username)

                // Xtream Password
                SecureField("Password", text: $playlist.password)
                    .textContentType(.password)
            }

            // Added date (read-only)
            LabeledContent("Added") {
                Text(playlist.addedAt, style: .date)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Stream Format Section

    private var streamFormatSection: some View {
        Section {
            Picker("Live Stream Format", selection: $playlist.streamFormat) {
                ForEach(PlaylistStreamFormat.allCases) { format in
                    Text(verbatim: format.displayName).tag(format)
                }
            }
        } header: {
            Text("Playback")
        } footer: {
            Text(streamFormatFooter)
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section {
            Toggle("Sync Enabled", isOn: $playlist.syncEnabled)

            if playlist.syncStatus == .syncing {
                HStack {
                    Text("Status")
                    Spacer()
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let lastSync = playlist.lastSyncDate {
                LabeledContent("Last Synced") {
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Sync Now") {
                showSync = true
            }
            .disabled(playlist.syncStatus == .syncing)

            if isStalker {
                Button("Download Full Catalog") {
                    showFullSync = true
                }
                .disabled(playlist.syncStatus == .syncing)
            }
        } header: {
            Text("Sync")
        } footer: {
            if isStalker {
                Text("""
                Movies and series load as you browse — nothing is prefetched. \
                Download the full catalog to make everything available offline and \
                searchable at once; this can take a while on large portals.
                """)
            }
        }
    }

    // MARK: - Delete Playlist

    func deletePlaylist() {
        if let cloudSync {
            let id = playlist.id
            Task { await cloudSync.deletePlaylist(id: id) }
        } else {
            PlaylistDeletion.delete(playlist, in: modelContext)
        }
        dismiss()
    }

    // MARK: - Helpers

    func formattedExpiry(_ raw: String) -> String {
        if let timestamp = TimeInterval(raw) {
            let date = Date(timeIntervalSince1970: timestamp)
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return raw
    }

    func isExpired(_ raw: String) -> Bool {
        guard let timestamp = TimeInterval(raw) else { return false }
        let date = Date(timeIntervalSince1970: timestamp)
        return date < Date()
    }
}
