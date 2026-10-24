//
//  Stored.swift
//  Runner
//
//  Created by GFWFighter on 10/24/23.
//

import Foundation

@propertyWrapper
struct Stored<Value: Codable> {
    private let key: String
    private var value: Value

    init(wrappedValue: Value, key: String) {
        self.key = key
        if
            let data = UserDefaults.standard.data(forKey: key),
            let stored = try? JSONDecoder().decode(Value.self, from: data)
        {
            self.value = stored
        } else {
            self.value = wrappedValue
        }
    }

    var wrappedValue: Value {
        get { value }
        set {
            value = newValue
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
