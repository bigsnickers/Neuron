//
//  File.swift
//  
//
//  Created by William Vabrinskas on 1/12/22.
//

import Foundation
import NumSwift

public class BatchNormalizer {
  @TestNaN public var gamma: Float = 1
  @TestNaN public var beta: Float = 0
  private var movingMean: Float = 0
  private var movingVariance: Float = 0
  private var normalizedActivations: [Float] = []
  private var standardDeviation: Float = 0
  private let momentum: Float = 0.9
  private let e: Float = 0.00005 //this is a standard smoothing term
  private let learningRate: Float
  
  public init(gamma: Float = 1, beta: Float = 0, learningRate: Float) {
    self.gamma = gamma
    self.beta = beta
    self.learningRate = learningRate
  }

  public func normalize(activations: [Float]) -> [Float] {
    
    let total = Float(activations.count)
    
    let mean = activations.reduce(0, +) / total
    
    let variance = activations.map { pow($0 - mean, 2) }.reduce(0, +) / total
        
    let std = sqrt(variance + e)
      
    standardDeviation = std
  
    let normalized = activations.map { ($0 - mean) / std }
    
    normalizedActivations = normalized
    
    movingMean = momentum * movingMean + (1 - momentum) * mean
    movingVariance = momentum * movingVariance + (1 - movingVariance) * variance
    
    let normalizedScaledAndShifted = normalized.map { gamma * $0 + beta }
    
    return normalizedScaledAndShifted
  }
  
  public func backward(gradient: [Float]) -> [Float] {
    let dBeta = gradient.reduce(0, +)
    
    guard gradient.count == normalizedActivations.count else {
      return gradient
    }
    
    var outputGradients: [Float] = []
    
    let n: Float = Float(gradient.count)
    
    let dxNorm: [Float] = gradient * gamma
    
    let combineXandDxNorm = normalizedActivations * dxNorm
    let dxNormTimesXNormSum: Float = combineXandDxNorm.sum
 
    let dxNormSum = dxNorm.reduce(0, +)
    let std = standardDeviation
    
    let dGamma = (gradient * normalizedActivations).sum
    
    let dx = ((1 / n) / std) * ((dxNorm * n) - (dxNormSum - normalizedActivations) * dxNormTimesXNormSum)
      
    outputGradients = dx
    
    gamma -= learningRate * dGamma
    beta -= learningRate * dBeta
    
    return outputGradients
  }
}
