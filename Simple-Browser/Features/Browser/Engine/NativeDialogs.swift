import AppKit

@MainActor enum NativeDialogs {
    static func confirm(
        title: String,
        message: String,
        accept: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        
        alert.addButton(withTitle: accept)
        alert.addButton(withTitle: "Cancel")
        
        return alert.runModal() == .alertFirstButtonReturn
    }
    
    static func message(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Ok")
        alert.runModal()
    }
    
    static func prompt(
        title: String,
        message: String,
        defaultText: String?
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        
        field.stringValue = defaultText ?? ""
        
        alert.accessoryView = field
        alert.addButton(withTitle: "Ok")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        
        return field.stringValue
    }
}
