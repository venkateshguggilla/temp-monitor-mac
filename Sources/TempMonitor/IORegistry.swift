import Foundation
import IOKit

/// Owns one IOKit object reference and releases it when dropped.
final class IOObject {
    let ref: io_object_t

    init?(_ ref: io_object_t) {
        guard ref != 0 else { return nil }
        self.ref = ref
    }

    deinit { IOObjectRelease(ref) }

    var entryID: UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(ref, &id)
        return id
    }

    var className: String {
        IOObjectCopyClass(ref)?.takeRetainedValue() as String? ?? "?"
    }

    func conforms(to cls: String) -> Bool { IOObjectConformsTo(ref, cls) != 0 }

    func property(_ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(ref, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    var parent: IOObject? {
        var p: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(ref, kIOServicePlane, &p) == KERN_SUCCESS else { return nil }
        return IOObject(p)
    }

    var children: [IOObject] {
        var it: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(ref, kIOServicePlane, &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        return IOObject.drain(it)
    }

    /// This entry and its ancestors, nearest first.
    var lineage: [IOObject] {
        var out = [self]
        while out.count < 32, let p = out.last!.parent { out.append(p) }
        return out
    }

    static func matching(_ cls: String) -> [IOObject] {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &it) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(it) }
        return drain(it)
    }

    static func bsd(_ name: String) -> IOObject? {
        IOObject(IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, name)))
    }

    private static func drain(_ it: io_iterator_t) -> [IOObject] {
        var out: [IOObject] = []
        while case let o = IOIteratorNext(it), o != 0 { out.append(IOObject(o)!) }
        return out
    }
}

enum Sysctl {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func int(_ name: String) -> Int? {
        var v: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        // Some values are 32-bit; the high half stays zero.
        return size == 4 ? Int(Int32(truncatingIfNeeded: v)) : Int(v)
    }
}
