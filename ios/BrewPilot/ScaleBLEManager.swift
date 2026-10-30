import CoreBluetooth
import Foundation

// BLE central for the ESP32 scale (SPEC 7). 10 Hz notify, 10-byte packet:
// u32 seq | i32 weight_cg | u8 flags | u8 battery (all little-endian).
// The scale is headless: tare / calibration / stream control all go over BLE.

enum ScaleUUID {
    static let service = CBUUID(string: "0000C0FF-EE00-4000-8000-00DECAFE0010")
    static let weight = CBUUID(string: "0000C0FF-EE00-4000-8000-00DECAFE0011")
    static let tare = CBUUID(string: "0000C0FF-EE00-4000-8000-00DECAFE0012")
    static let calib = CBUUID(string: "0000C0FF-EE00-4000-8000-00DECAFE0013")
    static let control = CBUUID(string: "0000C0FF-EE00-4000-8000-00DECAFE0014")
}

struct WeightPacket {
    var seq: UInt32
    var weightG: Double
    var settled: Bool
    var overload: Bool
    var batteryPct: UInt8

    static func parse(_ data: Data) -> WeightPacket? {
        guard data.count >= 10 else { return nil }
        let b = [UInt8](data)
        let seq = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        let cg = Int32(bitPattern: UInt32(b[4]) | UInt32(b[5]) << 8 | UInt32(b[6]) << 16 | UInt32(b[7]) << 24)
        return WeightPacket(
            seq: seq,
            weightG: Double(cg) / 100.0,
            settled: b[8] & 0x01 != 0,
            overload: b[8] & 0x02 != 0,
            batteryPct: b[9]
        )
    }
}

final class ScaleBLEManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var peripheralName: String?
    @Published var weightG = 0.0
    @Published var settled = false
    @Published var overload = false
    @Published var batteryPct: UInt8 = 0
    @Published var lastPacketAt: Date?
    @Published var droppedPackets = 0 // seq gaps this connection (SPEC: zero drops)

    var onWeight: ((Double, Bool) -> Void)? // grams, settled
    var onConnectionChange: ((Bool) -> Void)?

    private var central: CBCentralManager?
    private var scale: CBPeripheral?
    private var weightChar: CBCharacteristic?
    private var tareChar: CBCharacteristic?
    private var calibChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?
    private var lastSeq: UInt32?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard central?.state == .poweredOn else { return }
        central?.scanForPeripherals(withServices: [ScaleUUID.service], options: nil)
    }

    func tare() {
        guard let scale, let tareChar else { return }
        scale.writeValue(Data([0x01]), for: tareChar, type: .withResponse)
    }

    /// Tell the scale the mass currently on it (grams); it recomputes its
    /// scale factor and persists it. Tare empty first.
    func calibrate(knownGrams: Float) {
        guard let scale, let calibChar else { return }
        var g = knownGrams
        scale.writeValue(Data(bytes: &g, count: 4), for: calibChar, type: .withResponse)
    }

    func setStreaming(_ on: Bool) {
        guard let scale, let controlChar else { return }
        scale.writeValue(Data([on ? 0x01 : 0x00]), for: controlChar, type: .withResponse)
    }

    func setRate(_ hz: UInt8) {
        guard let scale, let controlChar else { return }
        scale.writeValue(Data([0x02, hz]), for: controlChar, type: .withResponse)
    }
}

extension ScaleBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { startScanning() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        scale = peripheral
        peripheralName = peripheral.name
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([ScaleUUID.service])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        weightChar = nil
        tareChar = nil
        calibChar = nil
        controlChar = nil
        onConnectionChange?(false)
        // Watchdog: a pending connect to the known scale never times out and
        // reconnects as soon as it advertises again, faster than a fresh scan.
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        startScanning()
    }
}

extension ScaleBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == ScaleUUID.service }) else { return }
        peripheral.discoverCharacteristics([ScaleUUID.weight, ScaleUUID.tare, ScaleUUID.calib, ScaleUUID.control], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            switch char.uuid {
            case ScaleUUID.weight:
                weightChar = char
                peripheral.setNotifyValue(true, for: char)
            case ScaleUUID.tare:
                tareChar = char
            case ScaleUUID.calib:
                calibChar = char
            case ScaleUUID.control:
                controlChar = char
            default:
                break
            }
        }
        lastSeq = nil
        droppedPackets = 0
        isConnected = true
        onConnectionChange?(true)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == ScaleUUID.weight,
              let data = characteristic.value,
              let packet = WeightPacket.parse(data) else { return }
        if let last = lastSeq, packet.seq &- last > 1 {
            droppedPackets += Int(packet.seq &- last &- 1)
        }
        lastSeq = packet.seq
        weightG = packet.weightG
        settled = packet.settled
        overload = packet.overload
        batteryPct = packet.batteryPct
        lastPacketAt = Date()
        onWeight?(packet.weightG, packet.settled)
    }
}
