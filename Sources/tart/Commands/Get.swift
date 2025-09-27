import ArgumentParser
import Foundation
import Darwin

fileprivate struct VMInfo: Encodable {
  let OS: OS
  let CPU: Int
  let Memory: UInt64
  let Disk: Int
  let DiskFormat: String
  let Size: String
  let Display: String
  let Running: Bool
  let State: String
  let NoGraphics: Bool?

  enum CodingKeys: String, CodingKey {
    case OS, CPU, Memory, Disk, DiskFormat, Size, Display, Running, State, NoGraphics
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OS, forKey: .OS)
    try container.encode(CPU, forKey: .CPU)
    try container.encode(Memory, forKey: .Memory)
    try container.encode(Disk, forKey: .Disk)
    try container.encode(DiskFormat, forKey: .DiskFormat)
    try container.encode(Size, forKey: .Size)
    try container.encode(Display, forKey: .Display)
    try container.encode(Running, forKey: .Running)
    try container.encode(State, forKey: .State)
    if let noGraphics = NoGraphics {
      try container.encode(noGraphics, forKey: .NoGraphics)
    } else {
      try container.encodeNil(forKey: .NoGraphics)
    }
  }
}

struct Get: AsyncParsableCommand {
  static var configuration = CommandConfiguration(commandName: "get", abstract: "Get a VM's configuration")

  @Argument(help: "VM name.", completion: .custom(completeLocalMachines))
  var name: String

  @Option(help: "Output format: text or json")
  var format: Format = .text

  func run() async throws {
    let vmDir = try VMStorageLocal().open(name)
    let vmConfig = try VMConfig(fromURL: vmDir.configURL)
    let memorySizeInMb = vmConfig.memorySize / 1024 / 1024

    // Check if VM is running with --no-graphics
    var noGraphics: Bool? = nil
    if try vmDir.running() {
      let lock = try vmDir.lock()
      let pid = try lock.pid()
      if pid > 0 {
        noGraphics = try checkNoGraphicsFlag(pid: pid)
      }
    }

    let info = VMInfo(OS: vmConfig.os, CPU: vmConfig.cpuCount, Memory: memorySizeInMb, Disk: try vmDir.sizeGB(), DiskFormat: vmConfig.diskFormat.rawValue, Size: String(format: "%.3f", Float(try vmDir.allocatedSizeBytes()) / 1000 / 1000 / 1000), Display: vmConfig.display.description, Running: try vmDir.running(), State: try vmDir.state().rawValue, NoGraphics: noGraphics)
    print(format.renderSingle(info))
  }

  private func checkNoGraphicsFlag(pid: pid_t) throws -> Bool {
    // Get process arguments using sysctl
    var mib = [CTL_KERN, KERN_PROCARGS2, pid]
    var size: size_t = 0

    // Get the size of the buffer needed
    if sysctl(&mib, 3, nil, &size, nil, 0) != 0 {
      // Process might have exited or we don't have permission
      return false
    }

    // Allocate buffer and get the data
    var buffer = [UInt8](repeating: 0, count: size)
    if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
      return false
    }

    // Parse the buffer to extract command line arguments
    // The format is: argc (4 bytes) + executable path + \0 + args...
    if size < 4 {
      return false
    }

    // Convert buffer to string and look for --no-graphics
    let data = Data(bytes: buffer, count: size)
    let str = String(data: data, encoding: .utf8) ?? ""

    return str.contains("--no-graphics")
  }
}
