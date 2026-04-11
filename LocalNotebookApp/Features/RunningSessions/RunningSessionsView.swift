import SwiftUI

struct RunningSessionsView: View {
    @Environment(AppSessionStore.self) private var appSession

    var body: some View {
        List {
            if appSession.runningSessions.isEmpty {
                Text("Open a notebook or script to start a session.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appSession.runningSessions) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.title)
                            .font(.headline)
                        HStack {
                            Text(session.kind.rawValue.uppercased())
                            Text(session.state.rawValue.capitalized)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
    }
}
