import Foundation

/// Routes explicit requests without granting a model or retrieved document permission to act.
public enum VyronAssistantRequestPolicy {
    public static func classify(_ text: String, projectIsOpen: Bool = false) -> VyronAssistantRequestKind {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !request.isEmpty else { return .standard }
        // Instructions in code, quotations, or a pasted document are reference material.
        guard !request.contains("```"), !request.hasPrefix(">"), !request.hasPrefix("\"") else {
            return .standard
        }
        let informational = [
            "how do i ", "how can i ", "how to ", "show me how ", "tell me how ", "explain ",
            "what if ", "what happens ", "can i ", "could i ", "can you explain ", "nasıl "
        ].contains(where: request.hasPrefix)
        let requestWithoutURLs = request.replacingOccurrences(of: #"https?://[^\s<>]+"#, with: " ",
                                                              options: .regularExpression)
        let websiteAnalysis = isWebsiteAnalysis(requestWithoutURLs, hasURL: requestWithoutURLs != request)
        let codeWork = [
            "implement ", "refactor ", "debug ", "write code", "write a function", "write a swift",
            "write a python", "fix the test", "fix this test", "fix the build", "fix this build"
        ].contains(where: request.hasPrefix) || (projectIsOpen && [
            "fix ", "add ", "update ", "build ", "create ", "change "
        ].contains(where: request.hasPrefix)) || [
            ".swift", ".py", ".js", ".ts", "viewmodel", "view model", "source code", "unused import",
            "failing test", "selection state", "compiler", "stack trace", "this function", "the function",
            "this method", "the method", "readme", "package.swift"
        ].contains(where: (websiteAnalysis ? requestWithoutURLs : request).contains)
        if !informational, !codeWork, websiteAnalysis { return .websiteAnalysis }
        if !informational, !codeWork, isComputerRequest(request, projectIsOpen: projectIsOpen) {
            return .computerTask
        }
        if codeWork { return .standard }
        if projectIsOpen, ["remove ", "rename ", "move ", "inspect "].contains(where: request.hasPrefix) {
            return .standard
        }
        let explicitWeb = [
            "search the web", "search online", "search internet", "look up ", "look this up", "browse ",
            "find online", "on the internet", "check online", "verify online", "internet'te", "internette",
            "web'de", "пошукай", "знайди в інтернеті"
        ].contains(where: request.contains)
        if explicitWeb { return .webSearch }
        if request.contains("https://") || request.contains("http://") { return .webSearch }
        let liveInformation = [
            "opening hours",
            "weather", "exchange rate", "stock price", "news about", "who is the ceo", "who is the president",
            "güncel", "bugün", "hava durumu", "nöbetçi", "сьогодні", "погода", "актуальн"
        ].contains(where: request.contains)
        let temporalQuestion = !projectIsOpen && [
            "latest ", "current ", "today", "tonight", "this week", "right now", "güncel", "bugün", "сьогодні"
        ].contains(where: request.contains)
        let places = [
            "pharmac", "restaurant", "hotel", "cafe", "café", "dentist", "hospital", "museum",
            "eczane", "restoran", "otel", "аптек", "ресторан", "готел"
        ].contains(where: request.contains)
        let finding = ["list", "find", "recommend", "near", " in ", "listele", "bul", "öner", "знайди", "список"]
            .contains(where: request.contains)
        return liveInformation || temporalQuestion || (places && finding) ? .webSearch : .standard
    }

    private static func isWebsiteAnalysis(_ request: String, hasURL: Bool) -> Bool {
        let scope = [
            "entire website", "whole website", "entire site", "whole site", "all subpages", "all its subpages",
            "all the subpages", "all pages", "all its pages", "every page", "every subpage", "including subpages",
            "including its subpages", "site-wide", "sitewide", "tüm web sitesi",
            "tüm sayfaları", "tüm alt sayfaları",
            "весь сайт", "усі сторінки", "всі сторінки"
        ].contains(where: request.contains)
        let action = [
            "analyze", "analyse", "analysis", "review", "audit", "summarize", "inspect", "analiz", "проаналіз"
        ].contains(where: request.contains)
        let website = ["website", "site", "subpage", "sayfa", "сайт"].contains(where: request.contains)
        let crawl = request.hasPrefix("crawl ") || request.hasPrefix("please crawl ")
        return (hasURL || website) && ((scope && action) || crawl)
    }

    private static func isComputerRequest(_ text: String, projectIsOpen: Bool) -> Bool {
        var request = text
        for prefix in ["please ", "can you ", "can u ", "could you ", "would you ", "i want you to "] {
            if request.hasPrefix(prefix) { request.removeFirst(prefix.count) }
        }
        if isSimulatorLaunchRequest(request) { return true }
        let operations = [
            "open ", "launch ", "activate ", "click ", "type ", "press ", "scroll ", "switch to ",
            "close ", "quit ", "inspect ", "delete ", "remove ", "uninstall ", "move ", "rename ",
            "aç ", "tıkla ", "uygulamayı aç", "відкрий ", "натисни "
        ]
        guard operations.contains(where: request.hasPrefix) else { return false }
        // File edits and source inspection remain in the selected project's tools.
        if ["source code", "swift file", "python file", "this function", "the function", "readme", "package.swift"]
            .contains(where: request.contains) { return false }
        if projectIsOpen {
            return [
                "mac", "safari", "chrome", "finder", "calculator", "outlook", "xcode", "settings",
                "browser", "application", " apps", "the app", "button", " menu", "window", "desktop",
                "keyboard", "mouse", "dock", "terminal"
            ].contains(where: request.contains)
        }
        return true
    }

    private static func isSimulatorLaunchRequest(_ text: String) -> Bool {
        let request = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        let words = request.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let operation = words.first, ["open", "launch", "run"].contains(operation) else { return false }
        let target = words.dropFirst()
        let namesSimulator = target.contains("simulator") || target.contains("devicehub")
            || zip(target, target.dropFirst()).contains { $0.0 == "device" && $0.1 == "hub" }
        let launchWords: Set<String> = [
            "the", "ios", "iphone", "ipad", "apple", "simulator", "device", "hub", "devicehub",
            "app", "application", "here", "now", "on", "my", "mac", "please", "for", "me"
        ]
        return namesSimulator && target.allSatisfy(launchWords.contains)
    }
}
