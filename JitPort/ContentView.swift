//  ContentView.swift
//  JitPort
//
//  Created by Muhammed Ramiza on 20/08/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedCategory: Category = .installed
    @State private var packages: [MacPortPackage] = []
    @State private var sortOrder = [KeyPathComparator(\MacPortPackage.name)]
    @State private var selection = Set<String>()
    @State private var upgradeSelection = Set<MacPortPackage.ID>()
    @State private var uninstallSelection = Set<String>()
    @State private var isLoading = false
    @State private var lastRefresh: Date?
    @State private var errorMessage: String?
    
    // Semantic version comparison
    private func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let components1 = v1.components(separatedBy: ".").compactMap { Int($0) }
        let components2 = v2.components(separatedBy: ".").compactMap { Int($0) }
        
        let length = max(components1.count, components2.count)
        for i in 0..<length {
            let c1 = i < components1.count ? components1[i] : 0
            let c2 = i < components2.count ? components2[i] : 0
            if c1 < c2 { return .orderedAscending }
            if c1 > c2 { return .orderedDescending }
        }
        return .orderedSame
    }

    var filteredPackages: [MacPortPackage] {
        switch selectedCategory {
        case .installed:
            return packages.filter { $0.isInstalled }
        case .requested:
            return packages.filter { $0.statuses.contains(.requested) }
        case .outdated:
            return packages.filter { $0.statuses.contains(.outdated) }
        case .inactive:
            return packages.filter { $0.statuses.contains(.inactive) }
        }
    }
    
    var categoryCounts: [Category: Int] {
        [
            .installed: packages.filter { $0.isInstalled }.count,
            .requested: packages.filter { $0.statuses.contains(.requested) }.count,
            .outdated: packages.filter { $0.statuses.contains(.outdated) }.count,
            .inactive: packages.filter { $0.statuses.contains(.inactive) }.count,
        ]
    }
    
    var selectedPackage: MacPortPackage? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return filteredPackages.first { $0.id == id }
    }
    
    var body: some View {
        NavigationSplitView {
            // Left Sidebar - Categories
            List(Category.allCases, id: \.self, selection: $selectedCategory) { category in
                Label(category.rawValue, systemImage: category.icon)
                    .foregroundStyle(selectedCategory == category ? .primary : .secondary)
                    .badge(categoryCounts[category] ?? 0)
            }
            .navigationTitle("MacPorts")
            .listStyle(.sidebar)
        } detail: {
            VStack(spacing: 0) {
                // Top toolbar with button
                HStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("Refreshing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(filteredPackages.count) packages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let lastRefresh {
                            Text("Updated \(lastRefresh, style: .relative) ago")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        Task { await refreshPackages() }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoading)
                    
                    Button(action: {
                        Task { await installSelected() }
                    }) {
                        Label("Install", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selection.isEmpty || isLoading)
                    
                    Button(action: {
                        Task { await upgradeSelected() }
                    }) {
                        Label("Upgrade", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(upgradeSelection.isEmpty || isLoading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                
                Divider()
                
                if let errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                }
                
                // Top/Bottom split: table on top, detail on bottom
                VSplitView {
                    if selectedCategory == .outdated {
                        Table(filteredPackages, selection: $selection, sortOrder: $sortOrder) {
                            TableColumn("Upgrade") { package in
                                Toggle("", isOn: Binding(
                                    get: { upgradeSelection.contains(package.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            upgradeSelection.insert(package.id)
                                        } else {
                                            upgradeSelection.remove(package.id)
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                            }
                            .width(min: 60, ideal: 60, max: 60)
                            
                            TableColumn("Name", value: \.name) { package in
                                HStack(spacing: 8) {
                                    Image(systemName: package.status.icon)
                                        .foregroundStyle(package.status.color)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(package.name)
                                            .lineLimit(1)
                                            .font(.system(.body, design: .monospaced))
                                        if let variant = package.variant, !variant.isEmpty {
                                            Text(variant)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                            .width(min: 220, ideal: 280, max: 350)
                            
                            TableColumn("Version", value: \.version) { package in
                                HStack(spacing: 4) {
                                    Text(package.version)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .width(min: 120, ideal: 150, max: 180)
                            
                            TableColumn("Latest") { package in
                                HStack(spacing: 6) {
                                    Text(package.latestVersion ?? "—")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.orange)
                                }
                            }
                            .width(min: 100, ideal: 130, max: 160)
                            
                            TableColumn("Category", value: \.description) { package in
                                Text(package.description)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }
                            .width(min: 200, ideal: 300, max: 500)
                        }
                        .tableStyle(.inset(alternatesRowBackgrounds: true))
                        .overlay {
                            if packages.isEmpty && !isLoading {
                                ContentUnavailableView(
                                    "No Packages",
                                    systemImage: "shippingbox",
                                    description: Text("Click Refresh to load packages from MacPorts")
                                )
                            }
                        }
                        .frame(minHeight: 300, maxHeight: .infinity)
                        .layoutPriority(1)
                    } else if selectedCategory == .inactive {
                        InactiveTable(filteredPackages: filteredPackages, selection: $selection, uninstallSelection: $uninstallSelection, compareVersions: compareVersions)
                            .frame(minHeight: 300, maxHeight: .infinity)
                            .layoutPriority(1)
                    } else {
                        Table(filteredPackages, selection: $selection, sortOrder: $sortOrder) {
                            TableColumn("Name", value: \.name) { package in
                                HStack(spacing: 8) {
                                    Image(systemName: package.status.icon)
                                        .foregroundStyle(package.status.color)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(package.name)
                                            .lineLimit(1)
                                            .font(.system(.body, design: .monospaced))
                                        if let variant = package.variant, !variant.isEmpty {
                                            Text(variant)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                            .width(min: 220, ideal: 280, max: 350)
                            
                            TableColumn("Version", value: \.version) { package in
                                HStack(spacing: 4) {
                                    Text(package.version)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .width(min: 120, ideal: 150, max: 180)
                            
                            TableColumn("Status") { package in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(package.status.color)
                                        .frame(width: 8, height: 8)
                                    Text(package.status.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .width(min: 100, ideal: 130, max: 160)
                            
                            TableColumn("Category", value: \.description) { package in
                                Text(package.description)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }
                            .width(min: 200, ideal: 300, max: 500)
                        }
                        .tableStyle(.inset(alternatesRowBackgrounds: true))
                        .overlay {
                            if packages.isEmpty && !isLoading {
                                ContentUnavailableView(
                                    "No Packages",
                                    systemImage: "shippingbox",
                                    description: Text("Click Refresh to load packages from MacPorts")
                                )
                            }
                        }
                        .frame(minHeight: 300, maxHeight: .infinity)
                        .layoutPriority(1)
                    }
                    
                    PackageDetailView(package: selectedPackage)
                        .layoutPriority(0)
                }
                .frame(maxHeight: .infinity)
            }
            .onChange(of: packages) {
                if selection.isEmpty, let first = filteredPackages.first {
                    selection = [first.id]
                }
            }
            .onChange(of: selectedCategory) {
                if let first = filteredPackages.first {
                    selection = [first.id]
                } else {
                    selection = []
                }
            }
            .navigationTitle(selectedCategory.rawValue)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task { await refreshPackages() }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadOrRefresh()
            }
        }
    }
    
    private func loadOrRefresh() async {
        if let loaded = loadPackages() {
            self.packages = loaded
        } else {
            await refreshPackages()
        }
    }
    
    private func refreshPackages() async {
        print("Starting package refresh...")
        isLoading = true
        errorMessage = nil
        defer {
            print("Package refresh finished.")
            isLoading = false
        }
        
        do {
            // Fetch installed packages (active + inactive)
            let installed = try await runPortCommand("installed")
            let installedDict = parseInstalled(installed)
            
            // Fetch requested packages (explicitly requested by user)
            let requested = try await runPortCommand("installed", "requested")
            let requestedNames = Set(self.parseInstalled(requested).keys)
            
            // Fetch inactive packages names and categories only
            let inactive = try await runPortCommand("list", "inactive")
            let inactiveDict = parseList(inactive)
            let inactiveNames = Set(inactiveDict.keys)
            
            // Fetch outdated packages
            let outdated = try await runPortCommand("outdated")
            let outdatedDict = parseOutdated(outdated)
            
            var newPackages: [MacPortPackage] = []
            
            // Add installed packages
            for (name, info) in installedDict {
                var statuses = Set<PackageStatus>()
                statuses.insert(.installed)
                
                if requestedNames.contains(name) { statuses.insert(.requested) }
                if inactiveNames.contains(name) { statuses.insert(.inactive) }
                if outdatedDict[name] != nil { statuses.insert(.outdated) }
                
                let latestVersion = outdatedDict[name]
                
                let category = inactiveNames.contains(name) ? inactiveDict[name]?.description : nil
                
                newPackages.append(MacPortPackage(
                    name: name,
                    version: info.version,
                    activeVersion: info.active,
                    inactiveVersions: [], // Will be populated for inactive
                    latestVersion: latestVersion,
                    variant: info.variant,
                    statuses: statuses,
                    description: category ?? "Installed via MacPorts",
                    category: category,
                    isInstalled: true
                ))
            }
            
            // Specifically fetch active versions for inactive packages as requested
            let inactivePackages = newPackages.filter { $0.statuses.contains(.inactive) }
            
            await withTaskGroup(of: (String, (String?, [String])).self) { group in
                for pkg in inactivePackages {
                    group.addTask {
                        let versions = await self.fetchPackageVersions(for: pkg.name)
                        return (pkg.name, versions)
                    }
                }
                
                var versionsMap: [String: (String?, [String])] = [:]
                for await (name, versions) in group {
                    versionsMap[name] = versions
                }
                
                // Update newPackages with active/inactive versions
                for i in 0..<newPackages.count {
                    if let versions = versionsMap[newPackages[i].name] {
                        newPackages[i] = MacPortPackage(
                            name: newPackages[i].name,
                            version: newPackages[i].version,
                            activeVersion: versions.0,
                            inactiveVersions: versions.1,
                            latestVersion: newPackages[i].latestVersion,
                            variant: newPackages[i].variant,
                            statuses: newPackages[i].statuses,
                            description: newPackages[i].description,
                            category: newPackages[i].category,
                            isInstalled: newPackages[i].isInstalled
                        )
                    }
                }
            }
            
            packages = newPackages.sorted { $0.name < $1.name }
            savePackages(packages)
            lastRefresh = Date()
        } catch {
            print("Error refreshing packages: \(error)")
            errorMessage = error.localizedDescription
            // Fall back to sample data for demo
            loadSampleData()
        }
    }
    
    // MARK: - Data Persistence
    
    private var storageURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let supportDir = paths[0].appendingPathComponent("JitPort", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        return supportDir.appendingPathComponent("packages.json")
    }
    
    private func savePackages(_ packages: [MacPortPackage]) {
        do {
            let data = try JSONEncoder().encode(packages)
            try data.write(to: storageURL)
        } catch {
            print("Error saving packages: \(error)")
        }
    }
    
    private func loadPackages() -> [MacPortPackage]? {
        do {
            let data = try Data(contentsOf: storageURL)
            return try JSONDecoder().decode([MacPortPackage].self, from: data)
        } catch {
            print("No saved packages found or error loading: \(error)")
            return nil
        }
    }
    
    private func fetchPackageVersions(for name: String) async -> (active: String?, inactive: [String]) {
        do {
            let output = try await runPortCommand("installed", name)
            var active: String? = nil
            var inactive: [String] = []
            
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("The following") { continue }
                
                // Pattern: name @version (active) ... or name @version
                let pattern = #/^\s*\S+\s+@(\S+)(?:\s+\((active)\))?/#
                if let match = trimmed.firstMatch(of: pattern) {
                    let version = String(match.output.1)
                    let activeKeyword = match.output.2.map(String.init)
                    
                    if activeKeyword == "active" {
                        active = version
                    } else {
                        inactive.append(version)
                    }
                }
            }
            return (active, inactive)
        } catch {
            print("Error fetching versions for \(name): \(error)")
            return (nil, [])
        }
    }
    
    private func upgradeSelected() async {
        guard !upgradeSelection.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        var packagesToUpgrade: [String] = []
        for id in upgradeSelection {
            if let package = packages.first(where: { $0.id == id }) {
                packagesToUpgrade.append(package.name)
            }
        }
        
        if !packagesToUpgrade.isEmpty {
            do {
                let packageArgs = packagesToUpgrade.joined(separator: " ")
                _ = try await runRootCommandAsync("/opt/local/bin/port upgrade \(packageArgs)")
                upgradeSelection.removeAll()
            } catch {
                errorMessage = "Failed to upgrade packages: \(error.localizedDescription)"
            }
        }
        
        await refreshPackages()
    }
    
    private func installSelected() async {
        guard !selection.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        for id in selection {
            if let index = packages.firstIndex(where: { $0.id == id }) {
                let package = packages[index]
                packages[index] = MacPortPackage(
                    name: package.name,
                    version: package.version,
                    activeVersion: package.activeVersion,
                    inactiveVersions: package.inactiveVersions,
                    latestVersion: package.latestVersion,
                    variant: package.variant,
                    statuses: package.statuses,
                    description: package.description,
                    category: package.category,
                    isInstalled: package.isInstalled
                )
                
                do {
                    _ = try await runRootCommandAsync("/opt/local/bin/port install \(package.name)")
                } catch {
                    errorMessage = "Failed to install \(package.name): \(error.localizedDescription)"
                }
            }
        }
        
        await refreshPackages()
    }
    
    private func runRootCommandAsync(_ command: String) async throws -> Bool {
        return try await Task.detached(priority: .userInitiated) {
            let scriptSource = "do shell script \"\(command)\" with administrator privileges"
            guard let appleScript = NSAppleScript(source: scriptSource) else {
                return false
            }
            
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            
            if let err = error {
                throw NSError(domain: "MacPortError", code: 1, userInfo: err as? [String : Any])
            }
            return true
        }.value
    }
    
    private func runPortCommand(_ args: String...) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/local/bin/port")
            process.arguments = args
            
            // Clear environment variables that might interfere with sub-process execution
            var env = ProcessInfo.processInfo.environment
            env.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
            process.environment = env
            
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errString = String(data: errData, encoding: .utf8) ?? "Unknown error"
                let cmd = args.joined(separator: " ")
                print("Port command '\(cmd)' failed with status \(process.terminationStatus): \(errString)")
                throw NSError(domain: "PortError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errString])
            }
            
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8) ?? ""
            let cmd = args.joined(separator: " ")
            print("Port command '\(cmd)' output length: \(output.count)")
            return output
        }.value
    }
    
    private func parseInstalled(_ output: String) -> [String: (version: String, variant: String?, active: String?, description: String?)] {
        var dict: [String: (String, String?, String?, String?)] = [:]
        
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("The following") else { continue }
            
            // Format: name @version (active/inactive) [variant]
            // inactive packages have no (active) marker
            let pattern = #/^\s*(\S+)\s+@(\S+)(?:\s+\((\w+)\))?(?:\s+\[([^\]]+)\])?/# 
            if let match = trimmed.firstMatch(of: pattern) {
                let name = String(match.output.1)
                let version = String(match.output.2)
                let activeState = match.output.3.map(String.init) ?? "inactive"
                let variant = match.output.4.map(String.init)
                
                let existing = dict[name]
                if activeState == "active" {
                    dict[name] = (version, variant, version, nil)
                } else {
                    dict[name] = (existing?.0 ?? version, existing?.1 ?? variant, existing?.2, nil)
                }
            }
        }
        return dict
    }
    
    private func parseOutdated(_ output: String) -> [String: String] {
        var dict: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("The following") else { continue }
            // Format: name @installed_version < @latest_version
            let components = trimmed.components(separatedBy: .whitespaces)
            if let index = components.firstIndex(of: "<") {
                let name = components[0]
                if index + 1 < components.count {
                    let latest = components[index + 1].replacingOccurrences(of: "@", with: "")
                    dict[name] = latest
                }
            }
        }
        return dict
    }
    
    private func parseList(_ output: String) -> [String: (version: String, description: String?)] {
        var dict: [String: (String, String?)] = [:]
        
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("Warning:") else { continue }
            
            // Format: name @version path
            // Updated to handle variable whitespace
            let pattern = #/^\s*(\S+)\s+@(\S+)\s+(.+)$/# 
            if let match = trimmed.firstMatch(of: pattern) {
                let name = String(match.output.1)
                let version = String(match.output.2)
                // No description in port list output, but we have the path/category
                let category = String(match.output.3)
                dict[name] = (version, category)
            }
        }
        return dict
    }
    
    private func loadSampleData() {
        packages = [
            MacPortPackage(name: "git", version: "2.43.0", activeVersion: "2.43.0", inactiveVersions: [], latestVersion: nil, variant: "+svn+credential_osxkeychain", statuses: [.installed], description: "Distributed version control system", category: "devel/git", isInstalled: true),
            MacPortPackage(name: "nodejs20", version: "20.10.0", activeVersion: "20.10.0", inactiveVersions: [], latestVersion: "20.11.0", variant: nil, statuses: [.installed, .outdated], description: "JavaScript runtime built on Chrome's V8 engine", category: "lang/nodejs20", isInstalled: true),
            MacPortPackage(name: "python312", version: "3.12.0", activeVersion: "3.12.0", inactiveVersions: [], latestVersion: nil, variant: "+readline+sqlite3", statuses: [.installed], description: "Interpreted, high-level programming language", category: "lang/python312", isInstalled: true),
            MacPortPackage(name: "swiftlint", version: "0.54.0", activeVersion: nil, inactiveVersions: [], latestVersion: nil, variant: nil, statuses: [.requested], description: "A tool to enforce Swift style and conventions", category: "devel/swiftlint", isInstalled: false),
            MacPortPackage(name: "swiftformat", version: "0.53.6", activeVersion: nil, inactiveVersions: [], latestVersion: nil, variant: nil, statuses: [.requested], description: "A code library for formatting Swift code", category: "devel/swiftformat", isInstalled: false),
            MacPortPackage(name: "xcodes", version: "1.4.0", activeVersion: nil, inactiveVersions: [], latestVersion: nil, variant: nil, statuses: [.requested], description: "Install and switch between multiple versions of Xcode", category: "devel/xcodes", isInstalled: false),
            MacPortPackage(name: "cocoapods", version: "1.13.0", activeVersion: "1.13.0", inactiveVersions: [], latestVersion: "1.14.0", variant: nil, statuses: [.installed, .outdated], description: "Dependency manager for Swift and Objective-C Cocoa projects", category: "devel/cocoapods", isInstalled: true),
            MacPortPackage(name: "alcatraz", version: "1.2.3", activeVersion: nil, inactiveVersions: ["1.2.3"], latestVersion: nil, variant: nil, statuses: [.installed, .inactive], description: "Package manager for Xcode (deprecated)", category: "devel/alcatraz", isInstalled: true),
        ]
        lastRefresh = Date()
    }
}

// MARK: - Models

enum Category: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case requested = "Requested"
    case outdated = "Outdated"
    case inactive = "Inactive"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .installed: return "shippingbox.fill"
        case .requested: return "arrow.down.circle.fill"
        case .outdated: return "exclamationmark.triangle.fill"
        case .inactive: return "archivebox.fill"
        }
    }
}

enum PackageStatus: String, Codable, CaseIterable {
    case requested = "Requested"
    case outdated = "Outdated"
    case inactive = "Inactive"
    case installed = "Installed"
    case updating = "Updating"
    
    var icon: String {
        switch self {
        case .requested: return "arrow.down.circle"
        case .outdated: return "exclamationmark.triangle"
        case .inactive: return "archivebox"
        case .installed: return "checkmark.circle.fill"
        case .updating: return "arrow.clockwise"
        }
    }
    
    var color: Color {
        switch self {
        case .requested: return .blue
        case .outdated: return .orange
        case .inactive: return .gray
        case .installed: return .green
        case .updating: return .purple
        }
    }
}

struct MacPortPackage: Identifiable, Equatable, Codable {
    var id: String { name }
    let name: String
    let version: String
    let activeVersion: String?
    let inactiveVersions: [String]
    let latestVersion: String?
    let variant: String?
    let statuses: Set<PackageStatus>
    let description: String
    let category: String?
    let isInstalled: Bool
    
    var status: PackageStatus {
        if statuses.contains(.outdated) { return .outdated }
        if statuses.contains(.requested) { return .requested }
        if statuses.contains(.inactive) { return .inactive }
        return .installed
    }
}

struct InactiveTable: View {
    let filteredPackages: [MacPortPackage]
    @Binding var selection: Set<String>
    @Binding var uninstallSelection: Set<String>
    let compareVersions: (String, String) -> ComparisonResult
    
    // Define an Identifiable row
    struct InactiveRow: Identifiable {
        let id: String // Unique ID for this row: name-version
        let pkg: MacPortPackage
        let inactiveVersion: String
    }
    
    var body: some View {
        let inactiveRows = filteredPackages.flatMap { pkg in
            pkg.inactiveVersions.map { InactiveRow(id: "\(pkg.name)-\($0)", pkg: pkg, inactiveVersion: $0) }
        }
        
        Table(inactiveRows, selection: $selection) {
            TableColumn("Uninstall") { row in
                Toggle("", isOn: Binding(
                    get: { uninstallSelection.contains(row.id) },
                    set: { isSelected in
                        if isSelected {
                            uninstallSelection.insert(row.id)
                        } else {
                            uninstallSelection.remove(row.id)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                // Only allow uninstalling if an active version exists
                .disabled(row.pkg.activeVersion == nil)
            }
            .width(min: 70, ideal: 70, max: 70)
            
            TableColumn("Name") { row in
                HStack(spacing: 8) {
                    Image(systemName: row.pkg.status.icon)
                        .foregroundStyle(row.pkg.status.color)
                        .frame(width: 16)
                    Text(row.pkg.name)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .width(min: 220, ideal: 280, max: 350)
            
            TableColumn("Version") { row in
                Text(row.inactiveVersion)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 120, ideal: 150, max: 180)
            
            TableColumn("Active Version") { row in
                HStack(spacing: 6) {
                    if let active = row.pkg.activeVersion, compareVersions(row.inactiveVersion, active) == .orderedAscending {
                        Text(active)
                            .font(.caption.monospaced())
                            .foregroundStyle(.green)
                    } else {
                        Text("—")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 100, ideal: 130, max: 160)
            
            TableColumn("Category") { row in
                Text(row.pkg.description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .width(min: 200, ideal: 300, max: 500)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}

struct PackageDetailView: View {
    let package: MacPortPackage?
    
    var body: some View {
        Group {
            if let package {
                VStack(alignment: .leading, spacing: 12) {
                    // Header row: icon, name, status
                    HStack(spacing: 12) {
                        Image(systemName: package.status.icon)
                            .font(.title2)
                            .foregroundStyle(package.status.color)
                            .frame(width: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(package.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .textSelection(.enabled)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(package.status.color)
                                    .frame(width: 8, height: 8)
                                Text(package.status.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if package.isInstalled {
                                    Text("•")
                                        .foregroundStyle(.tertiary)
                                    Text("Installed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if let variant = package.variant, !variant.isEmpty {
                            Text(variant)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    
                    Divider()
                    
                    // Detail fields
                    HStack(alignment: .top, spacing: 16) {
                        detailField("Version", value: package.version)
                        if package.status == .outdated, let latest = package.latestVersion {
                            detailField("Latest", value: latest, highlighted: true)
                        }
                        detailField("Category", value: package.category ?? "—")
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Category")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(package.description)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "No Package Selected",
                    systemImage: "info.circle",
                    description: Text("Select a package from the list to see its details")
                )
            }
        }
        .frame(minHeight: package == nil ? 0 : 140)
        .background(.background)
    }
    
    private func detailField(_ label: String, value: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospaced())
                .foregroundStyle(highlighted ? .orange : .primary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    ContentView()
}
