//
//  MainThreadBox.swift
//
//  Sendable wrapper for non-Sendable AppKit/Foundation types when their
//  reference is captured on a background queue solely to be unwrapped
//  back on the main thread.
//
//  Swift 6 strict concurrency rejects capturing NSMenuItem / NSImage /
//  TISInputSource (and similar legacy ObjC types that ship without
//  Sendable conformance) inside `DispatchQueue.main.async` closures.
//  Wrapping them here is correct as long as the wrapped value is only
//  consumed on the main thread — which is the contract every caller
//  here already follows.
//

import Foundation

struct MainThreadBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) { self.value = value }
}

/// Weak variant: holds a non-Sendable AnyObject across a queue hop without
/// pinning its lifetime. The wrapped reference is read on the main thread
/// where it's safe to deal with deallocation via Optional unwrapping.
final class MainThreadWeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?

    init(_ value: T?) { self.value = value }
}
