import Foundation
import CoreGraphics

/// SkyLight/CoreGraphics connection identifier.
typealias CGSConnectionID = Int32

/// Runtime resolver for the private `SkyLight.framework` symbols Dockman needs.
///
/// Symbols are bound with `dlopen`/`dlsym` (not at link time) so a missing symbol
/// on a future macOS is a recoverable runtime condition, not a launch failure
/// (docs/05 R-1). We try the modern `SLS*` name first, then the legacy `CGS*`
/// alias that CoreGraphics still re-exports.
final class SkyLightSymbols {
    typealias MainConnectionIDFn            = @convention(c) () -> CGSConnectionID
    typealias CopyManagedDisplaySpacesFn    = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
    typealias ManagedDisplayGetCurrentSpaceFn = @convention(c) (CGSConnectionID, CFString) -> UInt64
    typealias AddWindowsToSpacesFn          = @convention(c) (CGSConnectionID, CFArray, CFArray) -> Void
    typealias RemoveWindowsFromSpacesFn     = @convention(c) (CGSConnectionID, CFArray, CFArray) -> Void
    typealias MoveWindowsToManagedSpaceFn   = @convention(c) (CGSConnectionID, CFArray, UInt64) -> Void
    typealias CopySpacesForWindowsFn        = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias SpaceGetTypeFn                = @convention(c) (CGSConnectionID, UInt64) -> Int32

    let mainConnectionID:            MainConnectionIDFn?
    let copyManagedDisplaySpaces:    CopyManagedDisplaySpacesFn?
    let managedDisplayGetCurrentSpace: ManagedDisplayGetCurrentSpaceFn?
    let addWindowsToSpaces:          AddWindowsToSpacesFn?
    let removeWindowsFromSpaces:     RemoveWindowsFromSpacesFn?
    let moveWindowsToManagedSpace:   MoveWindowsToManagedSpaceFn?
    let copySpacesForWindows:        CopySpacesForWindowsFn?
    let spaceGetType:                SpaceGetTypeFn?

    static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    init() {
        // Prefer dlopen of the framework binary; fall back to RTLD_DEFAULT (-2),
        // since CoreGraphics has usually already loaded SkyLight into the process.
        var handle = dlopen(Self.skyLightPath, RTLD_NOW)
        if handle == nil { handle = UnsafeMutableRawPointer(bitPattern: -2) }

        func sym<T>(_ names: [String], _ type: T.Type) -> T? {
            for name in names {
                if let p = dlsym(handle, name) {
                    return unsafeBitCast(p, to: T.self)
                }
            }
            return nil
        }

        mainConnectionID = sym(
            ["SLSMainConnectionID", "CGSMainConnectionID"], MainConnectionIDFn.self)
        copyManagedDisplaySpaces = sym(
            ["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], CopyManagedDisplaySpacesFn.self)
        managedDisplayGetCurrentSpace = sym(
            ["SLSManagedDisplayGetCurrentSpace", "CGSManagedDisplayGetCurrentSpace"], ManagedDisplayGetCurrentSpaceFn.self)
        addWindowsToSpaces = sym(
            ["SLSAddWindowsToSpaces", "CGSAddWindowsToSpaces"], AddWindowsToSpacesFn.self)
        removeWindowsFromSpaces = sym(
            ["SLSRemoveWindowsFromSpaces", "CGSRemoveWindowsFromSpaces"], RemoveWindowsFromSpacesFn.self)
        moveWindowsToManagedSpace = sym(
            ["SLSMoveWindowsToManagedSpace", "CGSMoveWindowsToManagedSpace"], MoveWindowsToManagedSpaceFn.self)
        copySpacesForWindows = sym(
            ["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], CopySpacesForWindowsFn.self)
        spaceGetType = sym(
            ["SLSSpaceGetType", "CGSSpaceGetType"], SpaceGetTypeFn.self)
    }
}
