import AXSwift
import PromiseKit

/// The global Swindler state, lazily initialized.
public var state = State(delegate: OSXStateDelegate<AXSwift.UIElement, AXSwift.Application, AXSwift.Observer>())

/// An object responsible for propagating the given event. Used internally by the OSX delegates.
protocol EventNotifier: class {
  func notify<Event: EventType>(event: Event)
}

/// Implements StateDelegate using the AXUIElement API.
class OSXStateDelegate<
    UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
    where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
>: StateDelegate, EventNotifier {
  typealias Window = OSXWindowDelegate<UIElement, ApplicationElement, Observer>
  typealias Application = OSXApplicationDelegate<UIElement, ApplicationElement, Observer>
  private typealias EventHandler = (EventType) -> ()

  private var applications: [Application] = []
  private var eventHandlers: [String: [EventHandler]] = [:]

  var runningApplications: [ApplicationDelegate] { return applications.map({ $0 as ApplicationDelegate }) }
  var knownWindows: [WindowDelegate] { return applications.flatMap({ $0.knownWindows }) }

  // TODO: fix strong ref cycle
  // TODO: retry instead of ignoring an app/window when timeouts are encountered during initialization?

  init() {
    print("Initializing Swindler")
    for appElement in ApplicationElement.all() {
      Application.initialize(axElement: appElement, notifier: self).then { application in
        self.applications.append(application)
      }.error { error in
        let runningApplication = try? NSRunningApplication(processIdentifier: appElement.pid())
        print("Could not watch application \(runningApplication): \(error)")
      }
    }
    print("Done initializing")
  }

  func on<Event: EventType>(handler: (Event) -> ()) {
    let notification = Event.typeName
    if eventHandlers[notification] == nil {
      eventHandlers[notification] = []
    }

    // Wrap in a casting closure to preserve type information that gets erased in the dictionary.
    eventHandlers[notification]!.append({ handler($0 as! Event) })
  }

  func notify<Event: EventType>(event: Event) {
    if let handlers = eventHandlers[Event.typeName] {
      for handler in handlers {
        handler(event)
      }
    }
  }
}
