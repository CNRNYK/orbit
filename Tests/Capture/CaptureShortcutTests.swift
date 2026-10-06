import AppKit

@MainActor final class FakeShortcutRegistrar: ShortcutRegistering {
    var event: ((OrbitShortcutAction,Bool) -> Void)?
    var registered = [UInt32:OrbitShortcut](), removed = [UInt32]()
    var next: UInt32 = 1, fail = false, closed = false
    func register(_ shortcut: OrbitShortcut, action: OrbitShortcutAction) throws -> UInt32 {
        if fail { throw RecorderProblem(message:"Fixture registration refused") }
        let id = next; next += 1; registered[id] = shortcut; return id
    }
    func unregister(_ token: UInt32) { removed.append(token); registered.removeValue(forKey:token) }
    func reassign(_ token: UInt32, to action: OrbitShortcutAction) {}
    func shutdown() { closed = true; registered.removeAll(); event = nil }
}
@MainActor enum CaptureShortcutTests {
    static func run() async throws {
        let main = CaptureDisplayGeometry(id:1,appKitFrame:CGRect(x:0,y:0,width:1440,height:900),captureFrame:CGRect(x:0,y:0,width:1440,height:900),scale:2)
        let left = CaptureDisplayGeometry(id:2,appKitFrame:CGRect(x:-1920,y:0,width:1920,height:1080),captureFrame:CGRect(x:-1920,y:-180,width:1920,height:1080),scale:1)
        let above = CaptureDisplayGeometry(id:3,appKitFrame:CGRect(x:200,y:900,width:1280,height:720),captureFrame:CGRect(x:200,y:-720,width:1280,height:720),scale:2)
        let below = CaptureDisplayGeometry(id:4,appKitFrame:CGRect(x:100,y:-800,width:1280,height:800),captureFrame:CGRect(x:100,y:900,width:1280,height:800),scale:1)
        let displays = [main,left,above,below]
        for display in displays {
            let local = CGRect(x:20,y:30,width:300,height:200), global = display.captureRect(CGRect(x:20,y:30,width:300,height:200))
            precondition(display.localRect(global) == local)
            let selected = CaptureAreaSelection(display:display,rect:global)
            precondition(try! selected.sourceRect(in:displays,availableIDs:displays.map(\.id)) == local, "Source rectangles stay in points across Retina scales and negative origins")
        }
        var session = CaptureSelectionSession(displays:displays)
        session.hover(1); session.hover(2); precondition(session.highlighted == 2)
        precondition(session.begin(2)); session.hover(3); precondition(session.highlighted == 2 && !session.begin(3), "Dragging locks the display")
        let selected = session.selection(displayID:2,local:CGRect(x:50,y:70,width:3000,height:2000))!
        precondition(selected.displayID == 2 && selected.rect == left.captureRect(CGRect(x:50,y:70,width:1870,height:1010)))
        let recorder = RecorderState(); recorder.applyArea(selected); recorder.displayGeometry = { displays }
        precondition(recorder.displayID == 2 && recorder.area == selected.rect && recorder.selectedArea == selected, "Chosen secondary ID must propagate with its rectangle")
        let filterRequest = try CaptureDisplayRequest(displayID:recorder.displayID,selection:recorder.selectedArea,areaMode:true,current:displays,availableIDs:[1,2])
        precondition(filterRequest.displayID == 2 && filterRequest.sourceRect == CGRect(x:50,y:70,width:1870,height:1010), "Both capture filters consume the secondary ID and its point crop together")
        let fullRequest = try CaptureDisplayRequest(displayID:2,selection:nil,areaMode:false,current:displays,availableIDs:[1,2])
        precondition(fullRequest.displayID == 2 && fullRequest.sourceRect == nil)
        do { _ = try CaptureDisplayRequest(displayID:1,selection:selected,areaMode:true,current:displays,availableIDs:[1,2]); preconditionFailure("A secondary crop cannot be combined with the primary filter") } catch {}
        precondition(try! selected.sourceRect(in:displays,availableIDs:[1,2]) == CGRect(x:50,y:70,width:1870,height:1010))
        for current in [displays.filter { $0.id != 2 }, [CaptureDisplayGeometry(id:2,appKitFrame:left.appKitFrame,captureFrame:left.captureFrame,scale:2)]] {
            do { _ = try selected.sourceRect(in:current,availableIDs:[1,2]); preconditionFailure("Stale topology must be rejected") } catch { }
        }
        do { _ = try selected.sourceRect(in:displays,availableIDs:[1]); preconditionFailure("Missing capture display must be rejected") } catch { }
        session.cancel(); precondition(session.displays.isEmpty && session.dragging == nil && session.highlighted == nil && session.selection(displayID:2,local:.zero) == nil)
        let missing = RecorderState(); missing.displayID = 42; missing.requestSources = { RecorderSourceSnapshot(displays:[],windows:[]) }
        _ = await missing.loadSources(); precondition(missing.displayID == 42 && missing.notice?.contains("disconnected") == true)
        missing.requestSources = { throw RecorderProblem(message:"Fixture interrupted source enumeration") }; _ = await missing.loadSources()
        missing.requestSources = { RecorderSourceSnapshot(displays:[],windows:[]) }; _ = await missing.loadSources()
        precondition(missing.displayID == 42, "Transient enumeration failures must not silently replace an explicit display on retry")
        print("PASS: shared selection coordinates, negative/vertical origins, mixed scaling, drag locking/clamping, selected display propagation, cancellation and stale topology rejection")

        let suite = "Orbit-shortcuts-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.removePersistentDomain(forName:suite)
        let modes = Store(preferences:defaults)
        modes.recorderState.options.mode = "Window"; modes.screenshots.source.options.mode = "Selected area"
        precondition(modes.screenshots.source.options.mode == "Selected area" && modes.recorderState.options.mode == "Window")
        modes.setMenuCaptureMode("Full screen"); precondition(modes.screenshots.source.options.mode == "Full screen" && modes.recorderState.options.mode == "Full screen")
        modes.recorderState.options.mode = "Window"; modes.screenshots.source.options.mode = "Selected area"
        let restored = Store(preferences:defaults)
        precondition(restored.screenshots.source.options.mode == "Selected area" && restored.recorderState.options.mode == "Window")
        let recorderData = defaults.data(forKey:"orbit.recorder.options")!
        precondition((try! JSONDecoder().decode(RecorderOptions.self,from:recorderData)).mode == "Window")
        let state = KeyboardShortcutState(preferences:defaults), fake = FakeShortcutRegistrar()
        precondition(Set(state.assignments.values).count == 4)
        state.start(fake); precondition(fake.registered.count == 4)
        var fired = [OrbitShortcutAction](); state.perform = { fired.append($0) }
        fake.event?(.screenshot,true); fake.event?(.screenshot,true); fake.event?(.screenshot,false); fake.event?(.screenshot,true)
        precondition(fired == [.screenshot,.screenshot], "Held key must not repeat actions")
        let old = state.assignments[.screenshot]!, changed = OrbitShortcut(keyCode:8,modifiers:[.command,.control,.option])
        precondition(!state.assign(state.assignments[.recording],to:.screenshot) && state.assignments[.screenshot] == old)
        precondition(!state.assign(OrbitShortcut(keyCode:49,modifiers:.command),to:.screenshot))
        precondition(!state.assign(OrbitShortcut(keyCode:8,modifiers:[]),to:.screenshot))
        fake.fail = true; precondition(!state.assign(changed,to:.screenshot) && state.assignments[.screenshot] == old && fake.registered.values.contains(old))
        precondition(KeyboardShortcutState(preferences:defaults).assignments[.screenshot] == old)
        fake.fail = false; precondition(state.assign(changed,to:.screenshot) && fake.registered.count == 4 && !fake.registered.values.contains(old))
        precondition(KeyboardShortcutState(preferences:defaults).assignments[.screenshot] == changed)
        state.beginRecording(.screenshot); precondition(fake.registered.count == 4); fake.event?(.open,true); precondition(fired.count == 2 && state.assignments[.screenshot] == changed, "Recording an Orbit-owned duplicate must not dispatch or replace the working binding")
        state.finishRecording(nil); precondition(fake.registered.count == 4)
        precondition(state.assign(nil,to:.selector)); precondition(fake.registered.count == 3 && KeyboardShortcutState(preferences:defaults).assignments[.selector] == nil)
        fake.fail = true; state.restoreDefaults(); precondition(state.assignments[.screenshot] == changed && fake.registered.count == 3)
        fake.fail = false; state.restoreDefaults(); precondition(fake.registered.count == 4 && state.assignments[.screenshot] == old)
        // Restore defaults can swap assignments without losing the working registrations.
        _ = state.assign(nil,to:.open); _ = state.assign(nil,to:.screenshot)
        _ = state.assign(OrbitShortcutAction.open.defaultShortcut,to:.screenshot)
        _ = state.assign(OrbitShortcutAction.screenshot.defaultShortcut,to:.open)
        state.restoreDefaults(); precondition(fake.registered.count == 4 && state.assignments[.screenshot] == old)
        state.stop(); precondition(fake.closed && fake.registered.isEmpty && !state.running); state.receive(.open,pressed:true); precondition(fired.count == 2)
        for action in OrbitShortcutAction.allCases { _ = state.assign(nil,to:action) }; precondition(KeyboardShortcutState(preferences:defaults).assignments.isEmpty)
        let failing = KeyboardShortcutState(), backend = FakeShortcutRegistrar(); backend.fail = true; failing.start(backend); precondition(failing.warning != nil && backend.registered.isEmpty); backend.fail = false; precondition(failing.assign(failing.assignments[.open],to:.open) && backend.registered.count == 1, "An inactive assignment can retry registration"); failing.stop()
        print("PASS: shortcut persistence, disabled assignments, duplicates/reserved combinations, transactional rollback, key-repeat suppression, shortcut recording isolation and registration lifecycle")

        for phase in [RecorderState.Phase.recording,.paused] { precondition(CaptureShortcutRoute.resolve(.recording,phase:phase,blocked:true,dispatching:false,screenshotMode:"Window",recordingMode:"Full screen") == .stopRecording) }
        precondition(CaptureShortcutRoute.resolve(.screenshot,phase:.idle,blocked:false,dispatching:false,screenshotMode:"Selected area",recordingMode:"Window") == .screenshot("Selected area"))
        precondition(CaptureShortcutRoute.resolve(.recording,phase:.idle,blocked:false,dispatching:false,screenshotMode:"Selected area",recordingMode:"Window") == .startRecording("Window"))
        precondition(CaptureShortcutRoute.resolve(.screenshot,phase:.idle,blocked:false,dispatching:true,screenshotMode:"Window",recordingMode:"Window") == .ignore)
        let store = Store(preview:true,persistSelection:false), guarded: MenuBarController
        guarded = MenuBarController(store:store)
        for phase in [RecorderState.Phase.preparing,.countdown,.finishing] {
            store.recorderState.phase = phase; guarded.performShortcut(.recording); guarded.performShortcut(.screenshot); precondition(store.recorderState.phase == phase && !store.screenshots.working)
        }
        store.recorderState.phase = .idle; store.screenshots.working = true; guarded.performShortcut(.recording); precondition(store.recorderState.phase == .idle)
        store.screenshots.working = false; store.screenshots.selectingWindow = true; precondition(store.locked && !store.recorderState.canBegin()); guarded.performShortcut(.recording); precondition(store.recorderState.phase == .idle)
        store.screenshots.selectingWindow = false; store.terminalState.working = true; precondition(!MenuBarState(store:store).canNavigate)
        print("PASS: shortcut operation guards for selection, countdown, startup, saving, screenshot and terminal work without screen capture")
    }
}
