# CoreDataStack

## About
This is a template for a Core Data stack which can be used in apps needing basic support for background writes, main thread access, and background context for work. It has been ported to Swift from an [Objective-C repo](https://github.com/popwarsweet/KTZCoreDataStack).

## Example
To init the stack:
```swift
let coreDataStack = CoreDataStack(
            dataModelFilename: "ExampleModel",
            storeFilename: "ExampleDatabase",
            inMemory: false,
            dumpInvalidStore: true,
            finished: { (success, error) in
                if success {
                    print("successfully opened core data store")
                } else {
                    print("failed to open core data store: \(error)")
                }
        })
```

## Installation (ol' fashion ⌘C ⌘V)
Copy and paste `CoreDataStack.swift` into your project.

## Author
Kyle Zaragoza, popwarsweet@gmail.com

## License
CoreDataStack is available under the MIT license. See the LICENSE file for more info.
