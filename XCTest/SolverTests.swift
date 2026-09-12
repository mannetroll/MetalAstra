import XCTest
final class SolverTests: XCTestCase {
    func testDeterministicGPUAndCPUReferenceSuite() throws {
        try autoreleasepool { try NumericalTests.run(MetalResources(),realFFT:false) }
    }
    func testRealFFTProductionSolver() throws {
        try autoreleasepool { try NumericalTests.run(MetalResources(),realFFT:true) }
    }
}
