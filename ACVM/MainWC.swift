//
//  MainWC.swift
//  ACVM
//
//  Created by Ben Mackin on 12/7/20.
//

import Foundation
import Cocoa
import Network

class MainWC: NSWindowController {

    private var mainImageURL: URL?
    private var cdImageURL: URL?
    private var cdImageURL2: URL?
    private var virtMachine: VirtualMachine = VirtualMachine()
    
    @IBOutlet weak var startButton: NSToolbarItem!
    @IBOutlet weak var stopButton: NSToolbarItem!
    @IBOutlet weak var pauseButton: NSToolbarItem!
    @IBOutlet weak var configButton: NSToolbarItem!
    @IBOutlet weak var deleteButton: NSToolbarItem!
    @IBOutlet weak var headlessStartButton: NSToolbarItem!
    
    private var configButtonAction: Selector!
    
    @IBAction func didTapDeleteVMButton(_ sender: NSToolbarItem) {        
        let alert = NSAlert()
        alert.messageText = "Delete VM Configuration"
        alert.informativeText = "Are you sure you want to delete the VM Configuration " + virtMachine.config.vmname + "? Note that this will not remove any disk images. Those must be manually removed."
        
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        alert.beginSheetModal(for: self.window!) { (response) in
            if response == .alertFirstButtonReturn {
                do {
                    let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    let directoryURL = appSupportURL.appendingPathComponent("com.oltica.ACVM")
                    
                    try FileManager.default.removeItem(atPath: directoryURL.path + "/" + self.virtMachine.config.vmname + ".plist")
                    try FileManager.default.removeItem(atPath: self.virtMachine.config.nvram)
                    
                    if self.virtMachine.process != nil {
                        self.virtMachine.process?.terminate()
                        self.virtMachine.process = nil
                        self.virtMachine.state = 0
                        self.updateStates()
                    }
                    
                    NotificationCenter.default.post(name: Notification.Name(rawValue: "refreshVMList"), object: nil)
                    self.updateCurrentVMConfig()
                }
                catch {
                
                }
            }
        }
    }
    
    override func prepare (for segue: NSStoryboardSegue, sender: Any?)
    {
        let toolbarItem = sender as! NSToolbarItem
        
        if toolbarItem.label != "New" {
            if  let viewController = segue.destinationController as? VMConfigVC {
                viewController.virtMachine = virtMachine
            }
        }
    }
    
    @IBAction func didTapPauseButton(_ sender: NSToolbarItem) {
        virtMachine.client!.send(message: "{ \"execute\": \"stop\" }\r\n")
        virtMachine.state = 2
        updateStates()
    }
    
    @IBAction func didTapUnPauseButton(_ sender: NSToolbarItem) {
        virtMachine.client!.send(message: "{ \"execute\": \"cont\" }\r\n")
        virtMachine.state = 1
        updateStates()
    }
    
    @IBAction func didTapStopButton(_ sender: NSToolbarItem) {
        //virtMachine.process?.terminate()
        
        if virtMachine.state == 2 {
            virtMachine.client!.send(message: "{ \"execute\": \"cont\" }\r\n")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.virtMachine.client!.send(message: "{ \"execute\": \"system_powerdown\" }\r\n")
            }
        } else {
            virtMachine.client!.send(message: "{ \"execute\": \"system_powerdown\" }\r\n")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.cleanUpProcessOnStop()
        }
    }
    
    func cleanUpProcessOnStop() {
        virtMachine.process = nil
        virtMachine.state = 0
        
        if virtMachine.client != nil {
            virtMachine.client!.close()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.virtMachine.client = nil
            }
        }

        virtMachine.config.mountCDImage = false
        virtMachine.config.mountCDImage2 = false
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = appSupportURL.appendingPathComponent("com.oltica.ACVM")
          
        do {
            try FileManager.default.createDirectory (at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            let documentURL = directoryURL.appendingPathComponent (virtMachine.config.vmname + ".plist")
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            
            let data = try encoder.encode(virtMachine.config)
            try data.write(to: documentURL)
        }
        catch {
            
        }
        
        updateStates()
    }
    
    func setupNotifications()
    {
        NotificationCenter.default.addObserver(forName: Notification.Name(rawValue: "vmConfigChange"), object: nil, queue: nil) { (notification) in self.updateCurrentVMConfig(notification as NSNotification) }
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        configButtonAction = configButton.action
        
        updateStates()
        setupNotifications()
        
        configButton.action = nil
        startButton.action = nil
        deleteButton.action = nil
        stopButton.action = nil
        pauseButton.action = nil
        headlessStartButton.action = nil
    }
    
    private func updateStates() {
        
        if virtMachine.state == 0 { // Stopped
            stopButton.action = nil
            startButton.action = #selector(didTapStartButton(_:))
            headlessStartButton.action = #selector(didTapStartButton(_:))
            pauseButton.action = nil
            deleteButton.action = #selector(didTapDeleteVMButton(_:))
        } else if virtMachine.state == 1 { // Started
            stopButton.action = #selector(didTapStopButton(_:))
            startButton.action = nil
            headlessStartButton.action = nil
            pauseButton.action = #selector(didTapPauseButton(_:))
            deleteButton.action = nil
        } else if virtMachine.state == 2 { // Paused
            stopButton.action = #selector(didTapStopButton(_:))
            startButton.action = nil //#selector(didTapStartButton(_:))
            headlessStartButton.action = nil
            pauseButton.action = #selector(didTapUnPauseButton(_:))
            deleteButton.action = #selector(didTapDeleteVMButton(_:))
        }
        
        NotificationCenter.default.post(name: Notification.Name(rawValue: "qemuStatusChange"), object: virtMachine.state)
    }
    
    @objc
    private func processDidTerminate(_ notification: Notification) {
        guard let process = notification.object as? Process,
              process == virtMachine.process else {
            return
        }
        
        cleanUpProcessOnStop()
    }
    
    func updateCurrentVMConfig(_ notification: NSNotification) {
        configButton.action = nil
        startButton.action = nil
        headlessStartButton.action = nil
        pauseButton.action = nil
        deleteButton.action = nil
        stopButton.action = nil
        
        if let config = notification.userInfo?["config"] as? VirtualMachine {
            virtMachine = config
            configButton.action = configButtonAction
            updateStates()
        }
        
        if virtMachine.client != nil {
            let fileName = URL(fileURLWithPath: virtMachine.config.mainImage).lastPathComponent.replacingOccurrences(of: " ", with: "_")
            virtMachine.client?.send(message: "{ \"execute\": \"screendump\", \"arguments\": { \"filename\": \"/tmp/\(fileName)_screen.ppm\" } }\r\n")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.virtMachine.liveImage = NSImage(byReferencingFile: "/tmp/\(fileName)_screen.ppm")
            }
        }
        
    }
    
    func updateCurrentVMConfig() {
        configButton.action = nil
        startButton.action = nil
        deleteButton.action = nil
        stopButton.action = nil
    }
    
    @IBAction func didTapStartButton(_ sender: NSToolbarItem) {
        
        guard virtMachine.process == nil else {
            virtMachine.process?.terminate()
            cleanUpProcessOnStop()
            return
        }
        
        // read in config
        let mainImageFilePath = virtMachine.config.mainImage
        if FileManager.default.fileExists(atPath: mainImageFilePath) {
            let contentURL = URL(fileURLWithPath: mainImageFilePath)
            mainImageURL = contentURL
        }
        
        if virtMachine.config.mountCDImage {
            let cdImageFilePath = virtMachine.config.cdImage
            if FileManager.default.fileExists(atPath: cdImageFilePath) {
                let contentURL = URL(fileURLWithPath: cdImageFilePath)
                cdImageURL = contentURL
            }
        }
        else {
            cdImageURL = nil
        }
        
        if virtMachine.config.mountCDImage2 {
            let cdImageFilePath2 = virtMachine.config.cdImage2
            if FileManager.default.fileExists(atPath: cdImageFilePath2) {
                let contentURL = URL(fileURLWithPath: cdImageFilePath2)
                cdImageURL2 = contentURL
            }
        }
        else {
            cdImageURL2 = nil
        }
        
        guard let efiURL = Bundle.main.url(forResource: "QEMU_EFI", withExtension: "fd"),
              let mainImage = mainImageURL else {
            return
        }
        
        var icon = NSImage()
        icon = NSImage(named: "qemu")!
        
        let qemu = NSWorkspace()
        qemu.setIcon(icon, forFile: Bundle.main.url(
            forResource: "qemu-system-aarch64",
            withExtension: nil
        )!.path)
        
        /*qemu.setIcon(icon, forFile: Bundle.main.url(
            forResource: "qemu-system-x86_64",
            withExtension: nil
        )!.path)*/
        
        let process = Process()
        process.executableURL = Bundle.main.url(
            forResource: "qemu-system-" + virtMachine.config.architecture,
            withExtension: nil
        )
        
        let port = Int.random(in: 60000...65000)
        
        var nicOptions = ""
        
        if !virtMachine.config.nicOptions.isEmpty {
            nicOptions += ",\(virtMachine.config.nicOptions)"
        }
        
        if virtMachine.config.sshPortForward {
            nicOptions += ",hostfwd=tcp::10022-:22"
        }
        
        if virtMachine.config.rdpPortForward {
            nicOptions += ",hostfwd=tcp::13389-:3389"
        }
        
        var arguments: [String] = []
        
        if virtMachine.config.architecture == "aarch64" {
            arguments += [
                "-M", "virt,highmem=no",
                "-accel", "hvf",
                "-cpu", "host",
                "-name", virtMachine.config.vmname,
                "-smp", "cpus=" + String(virtMachine.config.cores) + ",sockets=1,cores=" + String(virtMachine.config.cores) + ",threads=1",
                "-m", String(virtMachine.config.ram) + "M",
                "-bios", efiURL.path,
                "-device", virtMachine.config.graphicOptions,
                "-device", "qemu-xhci,id=xhci", //,p2=8,p3=8",
                "-device", "usb-kbd",
                "-device", "usb-tablet",
                "-device", "virtio-rng-pci",
                "-nic", "user,model=virtio" + nicOptions,
                "-rtc", "base=localtime,clock=host",
                "-drive", "file=\(virtMachine.config.nvram),format=raw,if=pflash,index=1",
                "-device", "intel-hda",
                "-device", "hda-duplex",
                "-chardev", "socket,id=mon0,host=localhost,port=\(port),server,nowait",
                "-mon", "chardev=mon0,mode=control,pretty=on"
            ]
        } else if virtMachine.config.architecture == "x86_64" {
            arguments += [
                "-M", "pc",
                "-accel", "tcg,tb-size=32",
                "-cpu", "host",
                "-name", virtMachine.config.vmname,
                "-smp", "cpus=" + String(virtMachine.config.cores) + ",sockets=1,cores=" + String(virtMachine.config.cores) + ",threads=1",
                "-m", String(virtMachine.config.ram) + "M",
                "-bios", efiURL.path,
                "-device", virtMachine.config.graphicOptions,
                "-device", "qemu-xhci,id=xhci", //,p2=8,p3=8",
                "-device", "usb-kbd",
                "-device", "usb-tablet",
                "-device", "virtio-rng-pci",
                "-nic", "user" + nicOptions,
                "-rtc", "base=localtime,clock=host",
                "-drive", "file=\(virtMachine.config.nvram),format=raw,if=pflash,index=1",
                "-device", "intel-hda",
                "-device", "hda-duplex",
                "-chardev", "socket,id=mon0,host=localhost,port=\(port),server,nowait",
                "-mon", "chardev=mon0,mode=control,pretty=on"
            ]
        }
        
        var useCace = "directsync"
        if virtMachine.config.mainImageUseWTCache {
            useCace = "writethrough"
        }
        
        if virtMachine.config.mainImageUseVirtIO {
            arguments += [
                "-drive", "file=\(mainImage.path),if=virtio,id=boot,cache=\(useCace)",
            ]
        }
        else {
            arguments += [
                "-drive", "file=\(mainImage.path),if=none,id=boot,cache=\(useCace)",
                "-device", "nvme,drive=boot,serial=boot"
            ]
        }
        
        if let cdImageURL = cdImageURL {
            arguments += [
                "-drive", "file=\(cdImageURL.path),media=cdrom,if=none,id=cdimage",
                "-device", "usb-storage,drive=cdimage"
            ]
        }
        
        if let cdImageURL2 = cdImageURL2 {
            arguments += [
                "-drive", "file=\(cdImageURL2.path),media=cdrom,if=none,id=cdimage2",
                "-device", "usb-storage,drive=cdimage2"
            ]
        }
        
        if sender.label == "Headless" {
            arguments += [
                "-display", "none",
                "-serial", "stdio"
            ]
        } else if virtMachine.config.unhideMousePointer {
            arguments += [
                "-display","cocoa,show-cursor=on"
            ]
        }
        
        if 1==0 {
            arguments += [
                //"-usb", "-device", "nec-usb-xhci",
                //"-device", "usb-host,hostbus=0,hostaddr=0",
                //"-device", "usb-host,hostbus=1,hostaddr=1"
                // hostaddr=1 doesn't show anything in linux
                // hostaddr=0 shows a record in lsusb
                "-device", "usb-host,vendorid=0x0781,productid=0x5581"
            ]
        }

        process.arguments = arguments
        process.qualityOfService = .userInteractive
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(processDidTerminate(_:)),
            name: Process.didTerminateNotification,
            object: process
        )

        virtMachine.process = process
        virtMachine.state = 1
        
        do {
            try process.run()
            
            while !process.isRunning {
            
            }
            
            let client = TCPClient()
            //client.delegate = self
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if process.isRunning {
                    client.setupNetworkCommunication(UInt32(port))
                    client.initQMPConnection(vmName: self.virtMachine.config.vmname)
                    self.virtMachine.client = client
                }
            }
            
        } catch {
            NSLog("Failed to run, error: \(error)")
            
            virtMachine.process = nil
            virtMachine.state = 0
        }
        
        updateStates()
    }
}

/*extension MainWC: TCPClientDelegate {
  func received(message: Message) {
    var data = Data(message.message.utf8)
    
    print("VM: " + message.senderVM)
    print("Message: " + message.message)
    
    let newmessage = message.message.replacingOccurrences(of: "{\r\n    \"return\": {\r\n    }\r\n}\r\n", with: "")
    if newmessage.count > 0 {
        data = Data(newmessage.utf8)
    }
    
    do {
        let results: qmpReturn = try JSONDecoder().decode(qmpReturn.self, from: data)

        if let timestamp = results.timestamp?.seconds {
            print(timestamp)
        }
        
        if let event = results.event {
            print(event)
        }
        
        if let guest = results.data?.guest {
            print(guest)
        }
        
        if let reason = results.data?.reason {
            print(reason)
        }
    }
    catch {
        print(error)
    }
  }
}

struct qmpReturn: Decodable {
    let timestamp: qmpTimestamp?
    let event: String?
    let data: qmpData?

    private enum CodingKeys: String, CodingKey {
        case timestamp = "timestamp"
        case event = "event"
        case data = "data"
    }
}

struct qmpTimestamp: Decodable {
    let seconds: Int?
    let microseconds: Int?

    private enum CodingKeys: String, CodingKey {
        case seconds = "seconds"
        case microseconds = "microseconds"
    }
}

struct qmpData: Decodable {
    let guest: Bool?
    let reason: String?

    private enum CodingKeys: String, CodingKey {
        case guest = "guest"
        case reason = "reason"
    }
}*/
