//
//  File.swift
//
//
//  Created by William Vabrinskas on 5/5/22.
//

import Foundation
import NumSwift
import NumSwiftC

/// Performs a transposed 2d convolution on the inputs. Uses the same properties and initializers of `Conv2D`
public class TransConv2d: Conv2d {
  public override var encodingType: EncodingType { get { .transConv2d } set {}}
  public override var outputSize: TensorSize {
    var rows = inputSize.rows * strides.rows
    var columns = inputSize.columns * strides.columns
    
    if padding == .valid {
      rows = (inputSize.rows - 1) * strides.rows + filterSize.rows
      columns = (inputSize.columns - 1) * strides.columns + filterSize.columns
    }
  
    return TensorSize(array: [columns, rows, filterCount])
  }
  
  internal override func backward(_ input: Tensor, _ delta: Tensor) -> (input: Tensor, weight: Tensor, bias: Tensor) {
    let deltas = delta.value
    let flippedTransposed = filters.map { flip180($0) }.transposed() as [[[[Tensor.Scalar]]]]
    
    var weightGradients: [[[Tensor.Scalar]]] = []
    var inputGradients: [[[Tensor.Scalar]]] = []
    
    for i in 0..<deltas.count {
      let delta = deltas[i]
      let workingDeltasForInputs = delta

      for f in 0..<flippedTransposed.count {
        let filter = flippedTransposed[f]
        let kernel = filter[i]
        
        let gradientsForKernelIndex: [[Tensor.Scalar]] = device.conv2d(signal: workingDeltasForInputs,
                                                                             filter: kernel,
                                                                             strides: strides,
                                                                             padding: padding,
                                                                             filterSize: filterSize,
                                                                             inputSize: (outputSize.rows, outputSize.columns),
                                                                             outputSize: nil)

        let currentGradientsForFilter = inputGradients[safe: f, NumSwift.zerosLike((inputSize.rows, inputSize.columns))]
        let updatedGradientsForFilter = currentGradientsForFilter + gradientsForKernelIndex
        
        if let _ = inputGradients[safe: f] {
          inputGradients[f] = updatedGradientsForFilter
        } else {
          inputGradients.append(updatedGradientsForFilter)
        }
      }
      
      if trainable {
        let filterGradients = calculateFilterGradients(input, delta, index: i)
        //weightGradients.append(contentsOf: filterGradients)
        weightGradients.insert(contentsOf: filterGradients, at: 0)
      }
    }
      
    let biasGradients = input.value.map { $0.sum }

    return (Tensor(inputGradients), Tensor(weightGradients), Tensor(biasGradients))
  }
  
  internal override func calculateFilterGradients(_ input: Tensor, _ delta: [[Tensor.Scalar]], index: Int) -> Tensor.Data {
    var newGradientsForFilters: Tensor.Data = []
      
    for i in 0..<input.value.count {
      let forwardInputs = input.value[i]
      
      var filter = forwardInputs
      var signal = delta
      
      //TODO: fix this logic
      if strides.0 > 1 {
        filter = NumSwiftC.stridePad(signal: filter, strides: strides)
        filter = NumSwiftC.zeroPad(signal: filter,
                                   padding: NumSwiftPadding(top: 0,
                                                            left: 0,
                                                            right: strides.0 - 1,
                                                            bottom: strides.1 - 1))
      }

      if padding == .same {
        signal = NumSwiftC.zeroPad(signal: signal,
                                   filterSize: filterSize,
                                   inputSize: (outputSize.rows, outputSize.columns))
      }
      
      let fShape = filter.shape
      let sShape = signal.shape
      
      let newFilterSize = (fShape[safe: 1] ?? 0, fShape[safe: 0] ?? 0)
      let inputSize = (sShape[safe: 1] ?? 0, sShape[safe: 0] ?? 0)
      
      let result = device.conv2d(signal: signal,
                                 filter: filter,
                                 strides: (1,1),
                                 padding: .valid,
                                 filterSize: newFilterSize,
                                 inputSize: inputSize,
                                 outputSize: nil)
      
      newGradientsForFilters.append(result.reversed())
    }
    
    //all filter gradients will be mashed into one 3D array and then batched out later by num of filters
    //this way we dont have to store these gradients
    return newGradientsForFilters
  }
  
  internal override func conv(_ input: Tensor) -> [[[Tensor.Scalar]]] {
    let localFilters = filters.map { $0.value }
    var convolved: [[[Tensor.Scalar]]] = []
    let flatBiases = biases.value.flatten()
    
    for i in 0..<input.value.count {
      let localInput = input.value[i]
      var workingInput = NumSwiftC.stridePad(signal: localInput, strides: strides)

      let workingInputShape = workingInput.shape
      let inputRows = Double(outputSize.rows) - Double(workingInputShape[safe: 1, 0])
      let inputColumns = Double(outputSize.columns) - Double(workingInputShape[safe: 0, 0])
      
      let paddingTop = Int(ceil(inputRows / Double(2)))
      let paddingBottom = Int(floor(inputRows / Double(2)))
      let paddingLeft = Int(ceil(inputColumns / Double(2)))
      let paddingRight = Int(floor(inputColumns / Double(2)))
    
      let numPadding = NumSwiftPadding(top: paddingTop,
                                       left: paddingLeft,
                                       right: paddingRight,
                                       bottom: paddingBottom)
      
      workingInput = NumSwiftC.zeroPad(signal: workingInput, padding: numPadding)

      let newRows = workingInputShape[safe: 1, 0] + paddingTop + paddingBottom
      let newColumns = workingInputShape[safe: 0, 0] + paddingLeft + paddingRight
      
      for f in 0..<localFilters.count {
        let filter = localFilters[f]
        let kernel = filter[i]
        
        let gradientsForKernelIndex: [[Tensor.Scalar]] = device.conv2d(signal: workingInput,
                                                                             filter: kernel,
                                                                             strides: (1,1),
                                                                             padding: .same,
                                                                             filterSize: filterSize,
                                                                             inputSize: (newRows, newColumns),
                                                                             outputSize: nil)

        let currentGradientsForFilter = convolved[safe: f] ?? NumSwift.zerosLike((outputSize.rows, outputSize.columns))
        var updatedGradientsForFilter = currentGradientsForFilter + gradientsForKernelIndex
        
        if biasEnabled {
          updatedGradientsForFilter = updatedGradientsForFilter + flatBiases[f]
        }
        
        if let _ = convolved[safe: f] {
          convolved[f] = updatedGradientsForFilter
        } else {
          convolved.append(updatedGradientsForFilter)
        }
      }
      
    }
    
    let result = convolved
    return result
  }
  
  private func flip180(_ filter: Tensor) -> [[[Tensor.Scalar]]] {
    filter.value.map { $0.flip180() }
  }
  
}
