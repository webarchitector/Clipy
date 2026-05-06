//
//  UserDefaults+Combine.swift
//
//  Tiny Combine bridges over UserDefaults that mimic the semantics
//  RxSwift's `defaults.rx.observe(_:_:)` provided: emit the current
//  value on subscribe (so initial state is hydrated without an extra
//  manual call), and re-emit whenever any default changes. Combined
//  with `.removeDuplicates()`, downstream sinks only fire when the
//  watched key actually changed.
//

import Combine
import Foundation

extension UserDefaults {

    func boolPublisher(forKey key: String) -> AnyPublisher<Bool, Never> {
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .compactMap { [weak self] _ in self?.bool(forKey: key) }
            .prepend(bool(forKey: key))
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func integerPublisher(forKey key: String) -> AnyPublisher<Int, Never> {
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .compactMap { [weak self] _ in self?.integer(forKey: key) }
            .prepend(integer(forKey: key))
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func dictionaryPublisher(forKey key: String) -> AnyPublisher<[String: NSNumber], Never> {
        let initial = (dictionary(forKey: key) as? [String: NSNumber]) ?? [:]
        return NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .compactMap { [weak self] _ in self?.dictionary(forKey: key) as? [String: NSNumber] }
            .prepend(initial)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
