//
//  File.swift
//  
//
//  Created by William Vabrinskas on 2/17/22.
//

import Foundation
import XCTest
import GameKit
@testable import Neuron
import Combine

final class ConvTests: XCTestCase {
  var cancellables: Set<AnyCancellable> = []
  let mnist = MNIST()
  
  override func setUp() {
    super.setUp()

  }
  
  private lazy var brain: Brain = {
    let b = Brain(lossFunction: .crossEntropy,
                  initializer: .heNormal)

    b.add(LobeModel(nodes: 6272))
    b.add(LobeModel(nodes: 100, activation: .reLu))
    b.add(LobeModel(nodes: 10, activation: .none))

    b.add(modifier: .softmax)
    b.compile()

    return b
  }()
  
  private lazy var convBrain: ConvBrain = {
    let brain = ConvBrain(epochs: 100,
                          learningRate: 0.01,
                          inputSize: (28,28,1),
                          batchSize: 128,
                          fullyConnected: brain)
    
    brain.addConvolution(filterSize: (3,3,1), filterCount: 32) //need to specify filter size since this wont be built automatically
    brain.addMaxPool()
    brain.addConvolution(filterSize: (3,3,1), filterCount: 64) //need to specify filter size since this wont be built automatically
    brain.addMaxPool()
    
    return brain
  }()

  func testConvLobe() {
    var dataset: DatasetData?
    
    let expectation = XCTestExpectation()
    
    mnist.dataPublisher
      .receive(on: DispatchQueue.main)
      .sink { val in
        dataset = val
        expectation.fulfill()
      }
      .store(in: &self.cancellables)
    
    mnist.build()
    
    wait(for: [expectation], timeout: 1000)
    
    guard let dataset = dataset else {
      XCTFail()
      return
    }

    convBrain.train(data: dataset) { epoch in
      print(self.convBrain.loss.last)
    } completed: { loss in
      print(loss)
    }
  }

  func print3d(array: [[[Any]]]) {
    var i = 0
    array.forEach { first in
      print("index: ", i)
      first.forEach { print($0) }
      i += 1
    }
  }
}
