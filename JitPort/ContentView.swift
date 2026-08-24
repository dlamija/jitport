//  ContentView.swift
//  JitPort
//
//  Created by Muhammed Ramiza on 20/08/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedCategory: Category = .all
    @State private var packages: [MacPortPackage] = []
    @State private var sortOrder = [KeyPathComparator(\MacPortPackage.name)]
    @State private var selection = Set<MacPortPackage.ID>()
    @State private var upgradeSelection = Set<MacPortPackage.ID>()
    @State private var isLoading = false
    @State private var lastRefresh: Date?
    @State private var errorMessage: String?
    @State private var hasSynced = false
    
    var filteredPackages: [MacPortPackage] {
        switch selectedCategory {
        case .all:
            return packages
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
            .all: packages.count,
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
                        Task { await refreshPackages(sync: false) }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await refreshPackages(sync: !hasSynced)
            }
        }
    }
    
    private func refreshPackages(sync: Bool = false) async {
        print("Starting package refresh...")
        isLoading = true
        errorMessage = nil
        defer {
            print("Package refresh finished.")
            isLoading = false
        }
        
        do {
            if sync {
                print("Syncing MacPorts database...")
                _ = try await runRootCommandAsync("/opt/local/bin/port -s sync")
                hasSynced = true
            }
            
            // Fetch all data in parallel
            async let installedTask = runPortCommand("installed")
            async let allTask = runPortCommand("list")
            async let requestedTask = runPortCommand("installed", "requested")
            async let inactiveTask = runPortCommand("list", "inactive")
            async let outdatedTask = runPortCommand("outdated")
            
            let (installed, all, requested, inactive, outdated) = try await (installedTask, allTask, requestedTask, inactiveTask, outdatedTask)
            
            // Offload parsing to background
            let newPackages = try await Task.detached(priority: .userInitiated) {
                let installedDict = self.parseInstalled(installed)
                let allDict = self.parseList(all)
                let requestedNames = Set(self.parseInstalled(requested).keys)
                let inactiveDict = self.parseList(inactive)
                let inactiveNames = Set(inactiveDict.keys)
                let outdatedDict = self.parseOutdated(outdated)
                
                var packages: [MacPortPackage] = []
                
                for (name, info) in allDict {
                    var statuses = Set<PackageStatus>()
                    
                    if let installedInfo = installedDict[name] {
                        statuses.insert(.installed)
                        if requestedNames.contains(name) { statuses.insert(.requested) }
                        if inactiveNames.contains(name) { statuses.insert(.inactive) }
                        if outdatedDict[name] != nil { statuses.insert(.outdated) }
                    } else {
                        statuses.insert(.available)
                    }
                    
                    let latestVersion = outdatedDict[name]
                    let isInstalled = installedDict[name] != nil
                    
                    let category = inactiveNames.contains(name) ? inactiveDict[name]?.description : nil
                    
                    packages.append(MacPortPackage(
                        name: name,
                        version: info.version,
                        latestVersion: latestVersion,
                        variant: isInstalled ? installedDict[name]?.variant : nil,
                        statuses: statuses,
                        description: category ?? info.description ?? "Package in MacPorts",
                        category: category,
                        isInstalled: isInstalled
                    ))
                }
                return packages.sorted { $0.name < $1.name }
            }.value
            
            await MainActor.run {
                self.packages = newPackages
                self.lastRefresh = Date()
            }
        } catch {
            print("Error refreshing packages: \(error)")
            errorMessage = error.localizedDescription
            // Fall back to sample data for demo
            loadSampleData()
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
    
    private func parseInstalled(_ output: String) -> [String: (version: String, variant: String?, isActive: Bool, description: String?)] {
        var dict: [String: (String, String?, Bool, String?)] = [:]
        
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
                dict[name] = (version, variant, activeState == "active", nil)
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
            MacPortPackage(name: "git", version: "2.43.0", latestVersion: nil, variant: "+svn+credential_osxkeychain", statuses: [.installed], description: "Distributed version control system", category: "devel/git", isInstalled: true),
            MacPortPackage(name: "nodejs20", version: "20.10.0", latestVersion: "20.11.0", variant: nil, statuses: [.installed, .outdated], description: "JavaScript runtime built on Chrome's V8 engine", category: "lang/nodejs20", isInstalled: true),
            MacPortPackage(name: "python312", version: "3.12.0", latestVersion: nil, variant: "+readline+sqlite3", statuses: [.installed], description: "Interpreted, high-level programming language", category: "lang/python312", isInstalled: true),
            MacPortPackage(name: "swiftlint", version: "0.54.0", latestVersion: nil, variant: nil, statuses: [.requested], description: "A tool to enforce Swift style and conventions", category: "devel/swiftlint", isInstalled: false),
            MacPortPackage(name: "swiftformat", version: "0.53.6", latestVersion: nil, variant: nil, statuses: [.requested], description: "A code library for formatting Swift code", category: "devel/swiftformat", isInstalled: false),
            MacPortPackage(name: "xcodes", version: "1.4.0", latestVersion: nil, variant: nil, statuses: [.requested], description: "Install and switch between multiple versions of Xcode", category: "devel/xcodes", isInstalled: false),
            MacPortPackage(name: "cocoapods", version: "1.13.0", latestVersion: "1.14.0", variant: nil, statuses: [.installed, .outdated], description: "Dependency manager for Swift and Objective-C Cocoa projects", category: "devel/cocoapods", isInstalled: true),
            MacPortPackage(name: "alcatraz", version: "1.2.3", latestVersion: nil, variant: nil, statuses: [.installed, .inactive], description: "Package manager for Xcode (deprecated)", category: "devel/alcatraz", isInstalled: true),
        ]
        lastRefresh = Date()
    }
}

// MARK: - Models

enum Category: String, CaseIterable, Identifiable {
    case all = "All"
    case installed = "Installed"
    case requested = "Requested"
    case outdated = "Outdated"
    case inactive = "Inactive"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .installed: return "shippingbox.fill"
        case .requested: return "arrow.down.circle.fill"
        case .outdated: return "exclamationmark.triangle.fill"
        case .inactive: return "archivebox.fill"
        }
    }
}

enum PackageStatus: String, CaseIterable {
    case requested = "Requested"
    case outdated = "Outdated"
    case inactive = "Inactive"
    case installed = "Installed"
    case available = "Available"
    case updating = "Updating"
    
    var icon: String {
        switch self {
        case .requested: return "arrow.down.circle"
        case .outdated: return "exclamationmark.triangle"
        case .inactive: return "archivebox"
        case .installed: return "checkmark.circle.fill"
        case .available: return "plus.circle"
        case .updating: return "arrow.clockwise"
        }
    }
    
    var color: Color {
        switch self {
        case .requested: return .blue
        case .outdated: return .orange
        case .inactive: return .gray
        case .installed: return .green
        case .available: return .secondary
        case .updating: return .purple
        }
    }
}

struct MacPortPackage: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let version: String
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
        if statuses.contains(.installed) { return .installed }
        return .available
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
