// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronCompactionText {
    static var alreadyCompact: String {
        VyronResourceBundle.string("compactionAlreadyCompact", fallback: "There are no new messages to compact.")
    }
    static var attachments: String {
        VyronResourceBundle.string("compactionAttachments", fallback: "Remove unsent attachments before running /compact. Your attachments are still in the draft.")
    }
    static var completed: String {
        VyronResourceBundle.string("compactionCompleted", fallback: "Context compacted. Earlier messages remain in chat history.")
    }
    static var completedLimited: String {
        VyronResourceBundle.string("compactionCompletedLimited", fallback: "Context compacted from a bounded history excerpt. The full conversation remains in chat history.")
    }
    static var contextFull: String {
        VyronResourceBundle.string("compactionContextFull", fallback: "This message and the saved summary exceed the context limit. Shorten the message or start a new chat.")
    }
    static var failed: String {
        VyronResourceBundle.string("compactionFailed", fallback: "Context could not be compacted. The previous summary and full chat history are preserved.")
    }
    static var inputTooLarge: String {
        VyronResourceBundle.string("compactionInputTooLarge", fallback: "This compaction request is too large. Shorten its focus instructions or the latest message.")
    }
    static var invalidSummary: String {
        VyronResourceBundle.string("compactionInvalidSummary", fallback: "The model did not return a usable compact summary. Try /compact again.")
    }
    static var noHistory: String {
        VyronResourceBundle.string("compactionNoHistory", fallback: "Send a message before compacting this chat.")
    }
    static var preparing: String {
        VyronResourceBundle.string("compactionPreparing", fallback: "Compacting conversation context…")
    }
    static var saveFailed: String {
        VyronResourceBundle.string("compactionSaveFailed", fallback: "The compact summary could not be saved. Your previous context is preserved.")
    }
    static var wait: String {
        VyronResourceBundle.string("compactionWait", fallback: "Compaction will run after the current response.")
    }
}
