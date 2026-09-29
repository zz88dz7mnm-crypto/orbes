#!/usr/bin/env python3
"""Chequeo cruzado barato (sin compilar): tipos y miembros `.shared` que se usan en la app pero no se
declaran en el repo. Lo que queda son tipos de Apple (AppKit, SwiftUI…) o errores reales para revisar.
Uso: python3 scripts/dev/check-symbols.py"""
import re, pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]
files = [p for p in (root / "Sources").rglob("*.swift")]
decl = set()
decl_re = re.compile(r"\b(?:class|struct|enum|protocol|actor|typealias|associatedtype|let|var|func|case)\s+([A-Za-z_][A-Za-z0-9_]*)")
for p in files:
    t = p.read_text()
    decl.update(decl_re.findall(t))
    # generic params <T: ...>
    decl.update(re.findall(r"<\s*([A-Z][A-Za-z0-9]*)\s*[:,>]", t))
apple = set("""
Any AnyObject AnyView AnyCancellable AnyHashable Array Bool Character Double Float Int Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64
String Substring Set Dictionary Optional Result Error Never Void Data Date URL UUID Range ClosedRange Calendar TimeInterval Task
DispatchQueue DispatchWorkItem DispatchTime NSLock Thread Timer RunLoop ProcessInfo FileManager Bundle UserDefaults JSONEncoder JSONDecoder
JSONSerialization NotificationCenter Notification Process Pipe FileHandle CharacterSet Locale DateFormatter ISO8601DateFormatter
RelativeDateTimeFormatter NumberFormatter URLSession URLRequest HTTPURLResponse URLComponents URLQueryItem NSRegularExpression NSRange
NSString NSNumber NSObject NSError CGFloat CGPoint CGSize CGRect CGPath CGMutablePath CGColor CGContext CGImage CGAffineTransform
CGEventSource CGEventType CGWindowListCopyWindowInfo CGWindowLevelForKey CFTypeRef CFDictionary CACurrentMediaTime CAMediaTimingFunction
NSApplication NSApp NSWindow NSPanel NSView NSHostingView NSScreen NSEvent NSMenu NSMenuItem NSStatusBar NSStatusItem NSImage NSColor
NSBezierPath NSWorkspace NSRunningApplication NSCursor NSPasteboard NSAnimationContext NSOpenPanel NSSavePanel NSAlert NSTextField
NSSound NSFont NSAppleScript NSItemProvider NSDraggingInfo NSDragOperation NSWindowController NSApplicationDelegate NSTrackingArea
NSSize NSPoint NSRect NSDeviceDescriptionKey NSResponder NSDraggingDestination NSSharingService
View Text Image Color Font Shape Path Canvas TimelineView GraphicsContext Circle Capsule Rectangle RoundedRectangle Ellipse
VStack HStack ZStack LazyVStack LazyHStack LazyVGrid GridItem ScrollView ScrollViewReader ForEach Group GeometryReader Spacer Divider
Button Toggle Slider Picker Stepper TextField SecureField TextEditor Label Link Menu Form Section GroupBox LabeledContent DisclosureGroup
ProgressView Gauge ContentUnavailableView Animation Binding State StateObject ObservedObject EnvironmentObject Environment EnvironmentValues
EnvironmentKey Published ObservableObject FocusState AppStorage Namespace Edge EdgeInsets Alignment HorizontalAlignment VerticalAlignment
UnitPoint Angle LinearGradient RadialGradient AngularGradient Gradient StrokeStyle BlendMode ColorScheme ShapeStyle AnyShape ButtonStyle
ButtonStyleConfiguration PrimitiveButtonStyle ViewModifier ViewBuilder ToolbarItem NSViewRepresentable Context Anchor PreferenceKey
AnimatablePair Animatable Transaction TapGesture DragGesture LongPressGesture SimultaneousGesture ContentShape TextAlignment Visibility
Material Scene App Settings WindowGroup NSApplicationDelegateAdaptor ImageRenderer Text AttributedString Toolbar Tab TabView
Publishers Just PassthroughSubject CurrentValueSubject Combine Cancellable
AVAudioEngine AVAudioPlayerNode AVAudioFormat AVAudioPCMBuffer AVAudioPlayer AVAudioSession
SecItemCopyMatching SecItemAdd SecItemDelete OSStatus OSType SMAppService
AXUIElement AXUIElementCreateApplication AXUIElementCopyAttributeValue AXIsProcessTrusted AXIsProcessTrustedWithOptions
MainActor Sendable Hashable Equatable Identifiable Codable Decodable Encodable CaseIterable RawRepresentable Comparable CustomStringConvertible
Collection Sequence IteratorProtocol AppKit SwiftUI Foundation CoreGraphics QuartzCore Carbon ServiceManagement ScreenCaptureKit
CoreMedia UserNotifications UniformTypeIdentifiers ApplicationServices Darwin Glibc FoundationNetworking OrbexCore Swift Self Value Name
Level ModifierFlags CombineLatest CodingKey Decoder Encoder EmptyView List NavigationSplitView PhaseAnimator DatePicker AsyncImage
DispatchSource DispatchSourceTimer DispatchSemaphore MemoryLayout ObjCBool OpenConfiguration CommandLine Selector Int16 Int8
FileAttributeType RandomNumberGenerator UnsafeRawBufferPointer Continuation GetApplicationEventTarget GetEventParameter
InstallEventHandler RegisterEventHotKey UnregisterEventHotKey Type Error LocalizedError AsyncStream AsyncThrowingStream CheckedContinuation UnsafeMutablePointer
UnsafePointer UnsafeMutableRawPointer UnsafeRawPointer UnsafeMutableBufferPointer OpaquePointer Unmanaged ObjectIdentifier Mirror
""".split())
use_re = re.compile(r"\b([A-Z][A-Za-z0-9_]{2,})\b")
missing = {}
for p in files:
    if "Tests" in p.parts: continue
    t = p.read_text()
    t = re.sub(r'"""[\s\S]*?"""', '""', t)             # cadenas multilínea
    t = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', t)      # cadenas de una línea
    t = re.sub(r"//.*", "", t)
    t = re.sub(r"/\*[\s\S]*?\*/", "", t)
    for name in use_re.findall(t):
        if name in decl or name in apple: continue
        if name.startswith(("NS", "CG", "CF", "CA", "AV", "CM", "Sec", "kSec", "kCF", "AX", "SC", "UN", "MP", "SM", "UT", "IO", "Event")): continue
        if name.isupper() or re.fullmatch(r"[A-Z0-9_]+", name): continue   # constantes C (AF_UNIX, SIGPIPE…)
        missing.setdefault(name, set()).add(str(p.relative_to(root)))
for k in sorted(missing):
    print(f"{k:32s} {', '.join(sorted(missing[k]))[:110]}")
