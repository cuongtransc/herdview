import Foundation
import HerdviewCore

/// Polls one running Herdr session with `agent.list` every `pollSeconds`.
@MainActor
final class SessionWatcher {
    let host: HostConfig
    let session: HerdrSession
    private let socketPath: String
    private let store: AgentStore
    private var forward: SSHForwardProcess?
    private var task: Task<Void, Never>?
    private var stopped = false

    init(host: HostConfig, session: HerdrSession, store: AgentStore, socketBaseDir: String) {
        self.host = host
        self.session = session
        self.store = store
        if let ssh = host.ssh {
            let local = SSHForwardSpec.localSocketPath(baseDir: socketBaseDir, host: host.name, session: session.name)
            socketPath = local
            forward = SSHForwardProcess(spec: SSHForwardSpec(sshTarget: ssh, localSocketPath: local, remoteSocketPath: session.socketPath))
        } else {
            socketPath = session.socketPath
        }
    }

    func start() {
        store.setSocketPath(socketPath, host: host.name, session: session.name)
        stopped = false
        forward?.start()
        let interval = UInt64(max(1, host.pollSeconds)) * 1_000_000_000
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    func stop() {
        stopped = true
        task?.cancel()
        task = nil
        forward?.stop()
        store.setSocketPath(nil, host: host.name, session: session.name)
        store.removeSession(host: host.name, session: session.name)
    }

    private func poll() async {
        let path = socketPath
        let outcome = await Task.detached(priority: .utility) {
            Result { try HerdrClient.agentList(socketPath: path) }
        }.value
        guard !stopped, !Task.isCancelled else { return }

        switch outcome {
        case .success(let agents):
            store.apply(host: host.name, session: session.name, snapshot: agents)
        case .failure(let error):
            if case HerdrClientError.serverNotRunning = error {
                store.apply(host: host.name, session: session.name, snapshot: [])
            } else {
                NSLog("herdview: %@/%@ poll failed: %@", host.name, session.name, String(describing: error))
            }
        }
    }
}
