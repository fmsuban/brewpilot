import CoreBluetooth
import Foundation

// BLE central for the ESP32 scale (SPEC 7). 10 Hz notify, 10-byte packet:
// u32 seq | i32 weight_cg | u8 flags | u8 battery (all little-endian).

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

    var onWeight: ((Double) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private var central: CBCentralManager?
    private var scale: CBPeripheral?
    private var weightChar: CBCharacteristic?
    private var tareChar: CBCharacteristic?

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
    // TODO(day 3): calib write (float grams), control start/stop/rate,
    // auto-reconnect + "scale lost" surge after 1.5 s silence.
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
        onConnectionChange?(false)
        startScanning() // watchdog: auto-reconnect
    }
}

extension ScaleBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == ScaleUUID.service }) else { return }
        peripheral.discoverCharacteristics([ScaleUUID.weight, ScaleUUID.tare, ScaleUUID.calib, ScaleUUID.control], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == ScaleUUID.weight {
                weightChar = char
                peripheral.setNotifyValue(true, for: char)
            } else if char.uuid == ScaleUUID.tare {
                tareChar = char
            }
        }
        isConnected = true
        onConnectionChange?(true)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == ScaleUUID.weight,
              let data = characteristic.value,
              let packet = WeightPacket.parse(data) else { return }
        onWeight?(packet.weightG)
    }
}
