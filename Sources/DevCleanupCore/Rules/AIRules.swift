import Foundation

enum AIRules {
    static let all: [Rule] = [
        Rule(id: "claude-code-projects", title: "Claude Code conversation", group: .agents,
             cost: .lost("Claude Code conversations for this folder (resume history)"),
             locate: { subfolders(of: $0.inHome(".claude/projects")) }),

        Rule(id: "claude-code-file-history", title: "Claude Code file history", group: .agents,
             cost: .lost("undo snapshots of files Claude Code edited"),
             locate: { subfolders(of: $0.inHome(".claude/file-history")) }),

        Rule(id: "claude-code-old-versions", title: "Old Claude Code versions", group: .agents,
             cost: .redownload("only older versions; the current one stays"),
             locate: {
                 oldVersions(in: $0.inHome(".local/share/claude/versions"),
                             running: $0.inHome(".local/bin/claude"))
             }),

        Rule(id: "claude-desktop-cache", title: "Claude desktop cache", group: .agents,
             cost: .rebuild("recreated on next launch"),
             action: .removeContents,
             blockedBy: ["Claude"],
             locate: {
                 existing([
                     $0.inHome("Library/Application Support/Claude/Cache"),
                     $0.inHome("Library/Application Support/Claude/Code Cache"),
                     $0.inHome("Library/Application Support/Claude/GPUCache"),
                 ])
             }),

        Rule(id: "codex-sessions", title: "Codex sessions", group: .agents,
             cost: .lost("Codex conversation history for that month"),
             blockedBy: ["codex", "Codex"],
             locate: { env in
                 subfolders(of: env.inHome(".codex/sessions"))
                     .flatMap { subfolders(of: $0) }
             }),

        Rule(id: "opencode-logs", title: "opencode logs", group: .agents,
             cost: .lost("opencode logs"),
             action: .removeContents,
             blockedBy: ["opencode", "opencode-cli", "OpenCode"],
             locate: { existing([$0.inHome(".local/share/opencode/log")]) }),

        Rule(id: "cursor-cache", title: "Cursor cache", group: .editors,
             cost: .rebuild("recreated on next launch"),
             action: .removeContents,
             blockedBy: ["Cursor"],
             locate: {
                 existing([
                     $0.inHome("Library/Application Support/Cursor/Cache"),
                     $0.inHome("Library/Application Support/Cursor/CachedData"),
                     $0.inHome("Library/Application Support/Cursor/Code Cache"),
                     $0.inHome("Library/Application Support/Cursor/GPUCache"),
                     $0.inHome("Library/Application Support/Cursor/CachedExtensionVSIXs"),
                 ])
             }),

        Rule(id: "vscode-cache", title: "VS Code cache", group: .editors,
             cost: .rebuild("recreated on next launch"),
             action: .removeContents,
             blockedBy: ["Code", "Electron"],
             locate: {
                 existing([
                     $0.inHome("Library/Application Support/Code/Cache"),
                     $0.inHome("Library/Application Support/Code/CachedData"),
                     $0.inHome("Library/Application Support/Code/Code Cache"),
                     $0.inHome("Library/Application Support/Code/GPUCache"),
                     $0.inHome("Library/Application Support/Code/CachedExtensionVSIXs"),
                 ])
             }),

        Rule(id: "ollama-models", title: "Ollama models", group: .models,
             cost: .redownload("ollama pull downloads them again"),
             action: .removeContents,
             blockedBy: ["ollama", "Ollama"],
             locate: { existing([$0.inHome(".ollama/models")]) }),

        Rule(id: "lmstudio-models", title: "LM Studio models", group: .models,
             cost: .redownload("downloaded again from LM Studio"),
             action: .removeContents,
             blockedBy: ["LM Studio"],
             locate: {
                 existing([
                     $0.inHome(".lmstudio/models"),
                     $0.inHome(".cache/lm-studio/models"),
                 ])
             }),

        Rule(id: "huggingface-hub", title: "Hugging Face cache", group: .models,
             cost: .redownload("models download again on next use"),
             action: .removeContents,
             locate: { existing([$0.inHome(".cache/huggingface/hub")]) }),
    ]

    /// Every entry of `folder` except the newest one by modification date, the version
    /// `running` points at (when it resolves inside `folder`), and incomplete entries
    /// whose name ends in ".partial" or ".tmp". Entries can be files or folders;
    /// empty when `folder` is missing.
    private static func oldVersions(in folder: URL, running: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        let candidates = entries
            .filter { !isIncomplete($0) }
            .map { ($0, modificationDate(of: $0)) }
            .sorted { $0.1 < $1.1 }

        guard let newest = candidates.last else { return [] }
        let runningName = currentVersionName(in: folder, running: running)

        return candidates
            .filter { $0.0.lastPathComponent != newest.0.lastPathComponent &&
                $0.0.lastPathComponent != runningName }
            .map { $0.0 }
    }

    /// Name of the version entry `running` resolves to; nil when it points outside `folder`.
    private static func currentVersionName(in folder: URL, running: URL) -> String? {
        let root = folder.resolvingSymlinksInPath().path + "/"
        let target = running.resolvingSymlinksInPath().path
        guard target.hasPrefix(root) else { return nil }
        return target.dropFirst(root.count).split(separator: "/").first.map(String.init)
    }

    /// True for entries that are still downloading.
    private static func isIncomplete(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".partial") || url.lastPathComponent.hasSuffix(".tmp")
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
