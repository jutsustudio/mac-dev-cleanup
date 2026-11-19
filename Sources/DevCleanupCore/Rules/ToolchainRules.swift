import Foundation

enum ToolchainRules {
    static let all: [Rule] = [
        Rule(id: "npm-cache", title: "npm cache", group: .node,
             cost: .redownload("packages download again on the next npm install"),
             locate: { existing([$0.inHome(".npm/_cacache")]) }),

        Rule(id: "pnpm-store", title: "pnpm store", group: .node,
             cost: .redownload("packages download again on the next pnpm install"),
             locate: { existing([$0.inHome("Library/pnpm/store"),
                                 $0.inHome(".local/share/pnpm/store")]) }),

        Rule(id: "yarn-cache", title: "Yarn cache", group: .node,
             cost: .redownload("packages download again on the next yarn install"),
             action: .removeContents,
             locate: { existing([$0.inHome("Library/Caches/Yarn"),
                                 $0.inHome(".yarn/berry/cache")]) }),

        Rule(id: "bun-cache", title: "Bun cache", group: .node,
             cost: .redownload("packages download again on the next bun install"),
             action: .removeContents,
             blockedBy: ["bun"],
             locate: { existing([$0.inHome(".bun/install/cache")]) }),

        Rule(id: "deno-cache", title: "Deno cache", group: .node,
             cost: .redownload("modules download again on next run"),
             action: .removeContents,
             blockedBy: ["deno"],
             locate: { existing([$0.inHome("Library/Caches/deno")]) }),

        Rule(id: "playwright-browsers", title: "Playwright browsers", group: .node,
             cost: .redownload("npx playwright install downloads them again"),
             action: .removeContents,
             locate: { existing([$0.inHome("Library/Caches/ms-playwright")]) }),

        Rule(id: "pip-cache", title: "pip cache", group: .python,
             cost: .redownload("wheels download again on next pip install"),
             action: .removeContents,
             locate: { existing([$0.inHome("Library/Caches/pip")]) }),

        Rule(id: "uv-cache", title: "uv cache", group: .python,
             cost: .redownload("packages download again on next uv sync"),
             action: .removeContents,
             blockedBy: ["uv"],
             locate: { existing([$0.inHome(".cache/uv")]) }),

        Rule(id: "poetry-cache", title: "Poetry cache", group: .python,
             cost: .redownload("packages download again on next poetry install"),
             action: .removeContents,
             locate: { existing([$0.inHome("Library/Caches/pypoetry/cache"),
                                 $0.inHome("Library/Caches/pypoetry/artifacts")]) }),

        Rule(id: "cargo-registry", title: "Cargo registry cache", group: .rust,
             cost: .redownload("crates download again on next cargo build"),
             action: .removeContents,
             blockedBy: ["cargo"],
             locate: { existing([$0.inHome(".cargo/registry/cache"),
                                 $0.inHome(".cargo/registry/src"),
                                 $0.inHome(".cargo/git/checkouts")]) }),

        Rule(id: "go-build-cache", title: "Go build cache", group: .go,
             cost: .rebuild("next go build is slower"),
             action: .removeContents,
             blockedBy: ["go"],
             locate: { existing([$0.inHome("Library/Caches/go-build")]) }),

        Rule(id: "go-mod-cache", title: "Go module cache", group: .go,
             cost: .redownload("modules download again on next go build"),
             action: .command(["go", "clean", "-modcache"]),
             blockedBy: ["go"],
             locate: { env in
                 let vars = ProcessInfo.processInfo.environment
                 if vars["GOMODCACHE"] != nil || vars["GOPATH"] != nil { return [] }
                 return existing([env.inHome("go/pkg/mod")])
             }),

        Rule(id: "gradle-cache", title: "Gradle caches", group: .jvm,
             cost: .redownload("dependencies download again on next build"),
             action: .removeContents,
             blockedBy: ["java"],
             locate: { existing([$0.inHome(".gradle/caches"),
                                 $0.inHome(".gradle/wrapper/dists")]) }),

        Rule(id: "maven-repo", title: "Maven repository", group: .jvm,
             cost: .lost("downloaded jars come back on next build; jars you mvn install-ed locally are gone"),
             action: .removeContents,
             blockedBy: ["java"],
             locate: { existing([$0.inHome(".m2/repository")]) }),

        Rule(id: "android-cache", title: "Android cache", group: .android,
             cost: .redownload("recreated by Android tools"),
             action: .removeContents,
             blockedBy: ["studio"],
             locate: { existing([$0.inHome(".android/cache")]) }),

        Rule(id: "brew-cache", title: "Homebrew downloads", group: .brew,
             cost: .redownload("bottles download again on next brew install"),
             action: .removeContents,
             locate: { existing([$0.inHome("Library/Caches/Homebrew")]) }),
    ]
}
