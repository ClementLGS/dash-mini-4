import CoreBluetooth

/// Bluetooth pour la lumière LED (contrôleur ELK-BLEDOM / LEDBLE) : service FFF0, caractéristique FFF3.
/// Sur iOS l'adresse MAC n'existe pas : on retrouve la lumière par son nom (BLEDOM, ELK…) ou son service,
/// ou par un identifiant iOS / un morceau de nom saisi dans Réglages. L'identifiant trouvé est mémorisé.
final class BleLights: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private struct Job {
        let id: Int
        let addr: String
        let frames: [Data]
        let done: (String?) -> Void
    }

    private let service = CBUUID(string: "FFF0")
    private let characteristic = CBUUID(string: "FFF3")
    private var central: CBCentralManager!
    private var queue: [Job] = []
    private var job: Job?
    private var seq = 0
    private var jobTimer: Timer?
    private var idleTimer: Timer?
    private var target: CBPeripheral?
    private var writer: CBCharacteristic?

    /// Appelé quand l'état du Bluetooth change (pour prévenir la page).
    var onChange: (() -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    var available: Bool { central.state == .poweredOn }

    // MARK: - API

    func write(addr: String, csv: String, done: @escaping (String?) -> Void) {
        var frames: [Data] = []
        for part in csv.split(separator: ",") {
            if let d = BleLights.hexData(String(part)) { frames.append(d) }
        }
        if frames.isEmpty { done("trame Bluetooth invalide"); return }
        seq += 1
        queue.append(Job(id: seq, addr: addr.trimmingCharacters(in: .whitespaces), frames: frames, done: done))
        pump()
    }

    // MARK: - déroulement d'un ordre

    private func pump() {
        guard job == nil, !queue.isEmpty else { return }
        let j = queue.removeFirst()
        job = j
        idleTimer?.invalidate()
        jobTimer?.invalidate()
        jobTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.finish(j.id, "délai dépassé : lumière introuvable (éteinte, trop loin, ou occupée par l'appli LEDBLE)")
        }
        advance()
    }

    private func advance() {
        guard let j = job else { return }
        switch central.state {
        case .poweredOn:
            break
        case .unknown, .resetting:
            return // on attend centralManagerDidUpdateState
        default:
            finish(j.id, "Bluetooth indisponible ou refusé (Réglages iPad > Confidentialité > Bluetooth)")
            return
        }
        if let p = target, p.state == .connected, let w = writer {
            send(j, p, w)
            return
        }
        if let p = knownPeripheral(for: j.addr) {
            connect(p)
        } else {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    private func idKey(_ addr: String) -> String { "tdb.ble.id." + addr.lowercased() }

    private func knownPeripheral(for addr: String) -> CBPeripheral? {
        var uuid: UUID?
        if let u = UUID(uuidString: addr) {
            uuid = u
        } else if let s = UserDefaults.standard.string(forKey: idKey(addr)) {
            uuid = UUID(uuidString: s)
        }
        guard let id = uuid else { return nil }
        return central.retrievePeripherals(withIdentifiers: [id]).first
    }

    private func looksLikeMac(_ s: String) -> Bool {
        let parts = s.split(whereSeparator: { $0 == ":" || $0 == "-" })
        return parts.count == 6 && parts.allSatisfy { $0.count == 2 && UInt8($0, radix: 16) != nil }
    }

    private func matches(_ addr: String, _ p: CBPeripheral, _ name: String, _ services: [CBUUID]) -> Bool {
        if let u = UUID(uuidString: addr) { return p.identifier == u }
        let n = name.uppercased()
        if addr.isEmpty || looksLikeMac(addr) {
            return n.contains("BLEDOM") || n.contains("ELK") || n.contains("LEDBLE") || services.contains(service)
        }
        return name.lowercased().contains(addr.lowercased())
    }

    private func connect(_ p: CBPeripheral) {
        target = p
        writer = nil
        p.delegate = self
        central.connect(p, options: nil)
    }

    private func send(_ j: Job, _ p: CBPeripheral, _ w: CBCharacteristic) {
        let type: CBCharacteristicWriteType = w.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        for (i, f) in j.frames.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(i)) { [weak self] in
                guard let self = self, self.job?.id == j.id, p.state == .connected else { return }
                p.writeValue(f, for: w, type: type)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(j.frames.count) + 0.15) { [weak self] in
            self?.finish(j.id, nil)
        }
    }

    private func finish(_ id: Int, _ err: String?) {
        guard let j = job, j.id == id else { return }
        job = nil
        jobTimer?.invalidate()
        central.stopScan()
        if err != nil, let t = target, t.state != .connected {
            central.cancelPeripheralConnection(t)
            target = nil
            writer = nil
        }
        if err == nil {
            // On lâche la lumière après 30 s sans ordre (pour que l'appli LEDBLE puisse la reprendre).
            idleTimer?.invalidate()
            idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                guard let self = self, self.job == nil, let t = self.target else { return }
                self.central.cancelPeripheralConnection(t)
            }
        }
        j.done(err)
        pump()
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onChange?()
        if job != nil { advance() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let j = job, target == nil else { return }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        guard matches(j.addr, peripheral, name, services) else { return }
        central.stopScan()
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: idKey(j.addr))
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        target = nil
        writer = nil
        if let j = job { finish(j.id, "connexion à la lumière impossible") }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if target === peripheral {
            target = nil
            writer = nil
        }
        if let j = job { finish(j.id, "lumière déconnectée pendant l'ordre") }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let j = job else { return }
        guard let s = peripheral.services?.first(where: { $0.uuid == service }) else {
            finish(j.id, "ce n'est pas la bonne lumière (service FFF0 absent)")
            return
        }
        peripheral.discoverCharacteristics([characteristic], for: s)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let j = job else { return }
        guard let c = service.characteristics?.first(where: { $0.uuid == characteristic }) else {
            finish(j.id, "caractéristique FFF3 absente sur cette lumière")
            return
        }
        writer = c
        advance()
    }

    // MARK: - utilitaire

    static func hexData(_ s: String) -> Data? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count % 2 == 0 else { return nil }
        var d = Data()
        var i = t.startIndex
        while i < t.endIndex {
            let j = t.index(i, offsetBy: 2)
            guard let b = UInt8(t[i..<j], radix: 16) else { return nil }
            d.append(b)
            i = j
        }
        return d
    }
}
