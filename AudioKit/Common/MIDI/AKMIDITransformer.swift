//
//  AKMIDITransformer.swift
//  AudioKit For macOS
//
//  Created by Eric on 7/5/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

public protocol AKMIDITransformer {
    
    func doTransform(eventList:[AKMIDIEvent]) -> [AKMIDIEvent]
}

/// Default transformer functions
public extension AKMIDITransformer {
    func doTransform(eventList:[AKMIDIEvent]) -> [AKMIDIEvent] {
        AKLog("MIDI Transformer called")
        return eventList;
    }
}

