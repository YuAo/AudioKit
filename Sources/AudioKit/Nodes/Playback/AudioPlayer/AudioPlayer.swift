// Copyright AudioKit. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AVFoundation

/// Wrapper for AVAudioPlayerNode with a simplified API. The player exists in two interchangeable modes
/// either playing from memory (isBuffered) or streamed from disk. Longer files are recommended to be
/// played from disk. If you want seamless looping then buffer it. You can still loop from disk, but the
/// loop will not be totally seamless.

public class AudioPlayer: Node {
    /// Nodes providing input to this node.
    public var connections: [Node] { [] }

    /// The underlying player node
    public private(set) var playerNode = AVAudioPlayerNode()

    /// The output of the AudioPlayer and provides sample rate conversion if needed
    public private(set) var mixerNode = AVAudioMixerNode()

    /// The internal AVAudioEngine AVAudioNode
    public var avAudioNode: AVAudioNode { return mixerNode }

    /// Just the playerNode's property, values above 1 will have gain applied
    public var volume: AUValue {
        get { playerNode.volume }
        set { playerNode.volume = newValue }
    }

    /// Whether or not the playing is playing
    public internal(set) var isPlaying: Bool = false

    /// Whether or not the playing is paused
    public internal(set) var isPaused: Bool = false

    /// Will be true if there is an existing schedule event
    public var isScheduled: Bool { scheduleTime != nil }

    private var _isBuffered: Bool = false
    /// If the player is currently using a buffer as an audio source
    public var isBuffered: Bool {
        get { _isBuffered }
        set {
            guard newValue != _isBuffered else { return }
            _isBuffered = newValue

            if !newValue {
                buffer = nil
            }
        }
    }

    private var _isReversed: Bool = false

    /// Will reverse the file and convert to a buffered format if it's not already
    public var isReversed: Bool {
        get { _isReversed }
        set {
            guard newValue != isReversed else { return }
            _isReversed = newValue

            if isPlaying { stop() }

            if newValue && !isBuffered {
                isBuffered = true
                updateBuffer(force: true)
            }
        }
    }

    /// When buffered this should be called before scheduling events. For disk streaming
    /// this could be called at any time before a file is done playing
    public var isLooping: Bool = false {
        didSet {
            bufferOptions = isLooping ? .loops : .interrupts
        }
    }

    /// Indicates the player is in the midst of a seek operation
    public internal(set) var isSeeking: Bool = false

    /// Length of the audio file in seconds
    public var duration: TimeInterval {
        file?.duration ?? bufferDuration
    }

    /// Completion handler to be called when file or buffer is done playing.
    /// This also will be called when looping from disk,
    /// but no completion is called when looping seamlessly when buffered
    public var completionHandler: AVAudioNodeCompletionHandler?

    /// The file to use with the player. This can be set while the player is playing.
    public var file: AVAudioFile? {
        didSet {
            scheduleTime = nil
            let wasPlaying = isPlaying
            if wasPlaying { stop() }

            // Force the buffer to update with new file
            if isBuffered && file != oldValue {
                updateBuffer(force: true)
            }

            if wasPlaying {
                play()
            }
        }
    }

    /// The buffer to use with the player. This can be set while the player is playing
    public var buffer: AVAudioPCMBuffer? {
        didSet {
            isBuffered = buffer != nil
            scheduleTime = nil

            let wasPlaying = isPlaying
            if wasPlaying { stop() }

            if wasPlaying {
                play()
            }
        }
    }

    private var _isEditTimeEnabled: Bool = false
    /// Boolean that determines whether the edit time is enabled (default: true)
    public var isEditTimeEnabled: Bool {
        get { _isEditTimeEnabled }
        set(preference) {
            if preference == false {
                savedEditStartTime = editStartTime
                savedEditEndTime = editEndTime
                editStartTime = 0
                editEndTime = 0
                _isEditTimeEnabled = false
            } else {
                editStartTime = savedEditStartTime ?? 0
                editEndTime = savedEditEndTime ?? 0
                _isEditTimeEnabled = true
            }
        }
    }

    private var _editStartTime: TimeInterval = 0
    /// Get or set the edit start time of the player.
    public var editStartTime: TimeInterval {
        get { _editStartTime }
        set {
            _editStartTime = newValue.clamped(to: 0...duration)
        }
    }

    private var _editEndTime: TimeInterval = 0
    /// Get or set the edit end time of the player. Setting to 0 will effectively remove
    /// the edit and set to the duration of the player
    public var editEndTime: TimeInterval {
        get {
            _editEndTime
        }

        set {
            var newValue = newValue
            if newValue == 0 {
                newValue = duration
            }
            _editEndTime = newValue.clamped(to: 0...duration)
        }
    }

    // MARK: - Internal properties

    // Time in audio file where track was stopped (allows retrieval of playback time after playerNode is paused)
    var pausedTime: TimeInterval = 0.0

    // the last time scheduled. Only used to check if play() should schedule()
    var scheduleTime: AVAudioTime?

    // saved edit times to load when user enables isEditTimeEnabled property
    var savedEditStartTime: TimeInterval?
    var savedEditEndTime: TimeInterval?

    var bufferOptions: AVAudioPlayerNodeBufferOptions = .interrupts

    var bufferDuration: TimeInterval {
        guard let buffer = buffer else { return 0 }
        return TimeInterval(buffer.frameLength) / buffer.format.sampleRate
    }

    /// - Returns: The total frame count that is being playing.
    /// Differs from the audioFile.length as this will be updated with the edited amount
    /// of frames based on startTime and endTime
    var frameCount: AVAudioFrameCount = 0
    var startingFrame: AVAudioFramePosition?
    var endingFrame: AVAudioFramePosition?

    var engine: AVAudioEngine? { mixerNode.engine }

    // MARK: - Internal functions

    func internalCompletionHandler() {
        guard !isSeeking,
              isPlaying,
              engine?.isInManualRenderingMode == false else { return }

        scheduleTime = nil
        isPlaying = false
        completionHandler?()

        if !isBuffered, isLooping, engine?.isRunning == true {
            if !isEditTimeEnabled {
                editStartTime = 0
                editEndTime = 0
            }
            play()
            return
        }
    }

    // MARK: - Init

    /// Create an AudioPlayer with default properties and nothing pre-loaded
    public init() {}

    /// Create an AudioPlayer from file, optionally choosing to buffer it
    public init?(file: AVAudioFile, buffered: Bool? = nil) {
        do {
            try load(file: file, buffered: buffered)
        } catch let error as NSError {
            Log(error, type: .error)
            return nil
        }
    }

    /// Create an AudioPlayer from URL, optionally choosing to buffer it
    public convenience init?(url: URL, buffered: Bool? = nil) {
        self.init()
        do {
            try load(url: url, buffered: buffered)
        } catch let error as NSError {
            Log(error, type: .error)
            return nil
        }
    }

    /// Create an AudioPlayer from an existing buffer
    public convenience init?(buffer: AVAudioPCMBuffer) {
        self.init()
        load(buffer: buffer)
    }

    deinit {
        buffer = nil
        file = nil
    }

    // MARK: - Loading

    /// Load file at a URL, optionally buffered
    /// - Parameters:
    ///   - url: URL of the audio file
    ///   - buffered: Boolean of whether you want the audio buffered
    public func load(url: URL, buffered: Bool? = nil) throws {
        let file = try AVAudioFile(forReading: url)
        try load(file: file, buffered: buffered)
    }

    /// Load an AVAudioFIle, optionally buffered
    /// - Parameters:
    ///   - file: File to play
    ///   - buffered: Boolean of whether you want the audio buffered
    ///   - preserveEditTime: Boolean - keep the previous edit time region? (default: false)
    public func load(file: AVAudioFile,
                     buffered: Bool? = nil,
                     preserveEditTime: Bool = false) throws {
        var formatHasChanged = false

        if let currentFile = self.file,
           currentFile.fileFormat != file.fileFormat {
            Log("Format has changed, player will be reconnected with format", file.fileFormat)
            engine?.disconnectNodeInput(playerNode)
            formatHasChanged = true
        }

        self.file = file

        if preserveEditTime == false {
            // Clear edit time preferences after file is loaded
            editStartTime = 0
            editEndTime = 0
        }

        if formatHasChanged {
            makeInternalConnections()
        }

        if let buffered = buffered {
            isBuffered = buffered
        }

        if isBuffered {
            updateBuffer()
        }
    }

    /// Load a buffer for playing directly
    /// - Parameter buffer: Buffer to play
    public func load(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
        isBuffered = true
    }
}

extension AudioPlayer: HasInternalConnections {
    /// Check if the playerNode is already connected to the mixerNode
    var isPlayerConnectedToMixerNode: Bool {
        var iBus = 0
        let engine = self.playerNode.engine
        if let engine = engine {
            while iBus < playerNode.numberOfOutputs {
                for playercp in engine.outputConnectionPoints(for: playerNode, outputBus: iBus)
                where playercp.node == mixerNode {
                    return true
                }
                iBus += 1
            }
        }
        return false
    }

    /// called in the connection chain to attach the playerNode
    public func makeInternalConnections() {
        guard let engine = engine else {
            Log("Engine is nil", type: .error)
            return
        }
        if playerNode.engine == nil {
            engine.attach(playerNode)
        }
        if !isPlayerConnectedToMixerNode {
            engine.connect(playerNode, to: mixerNode, format: file?.processingFormat)
        }
    }
}
