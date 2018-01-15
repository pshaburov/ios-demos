import UIKit
import ARKit
import SceneKit

class ViewController: UIViewController {

    @IBOutlet var sceneView: ARView!
    @IBOutlet var bottomBar: BottomBar!
    
    private var models: [Model]!
    private var currentModel: Model?
    private var modelNodeModel: SCNNode?
    private var planeNodeModel: SCNNode?
    private var lightNodeModel: SCNNode?
    
    private let modelFactory = ModelFactory()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        models = modelFactory.parseJSON()
        setUpFirstModel()
        setUpModelsOnView()
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.isLightEstimationEnabled = true;

        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    private func setUpModelsOnView() {
        bottomBar.addModelButtons(models: models ?? [])
        bindButtons()
    }
    
    private func setUpFirstModel() {
        guard let firstModelName = models.first?.fileName else { return }
        setNewModel(with: firstModelName)
    }
    
    private func bindButtons() {
        bottomBar.onTap = { [weak self] (modelName) in
            guard let strongSelf = self else { return }
            strongSelf.setNewModel(with: modelName)
        }
    }
    
    private func setNewModel(with modelName: String) {
        guard let model = models.first(where: { $0.fileName == modelName }) else { return }
        currentModel = model
        addNodes(to: model)
    }
    
    private func addNodes(to model: Model) {
        let assetpath = model.filePath + model.fileName + model.fileExtension
        model.nodes.forEach { node in
            let assetName = node.name
            switch node.type {
            case .object:
                modelNodeModel = createSceneNodeForAsset(assetName, assetPath: assetpath)
            case .plane:
                planeNodeModel = createSceneNodeForAsset(assetName, assetPath: assetpath)
            case .light:
                lightNodeModel = createSceneNodeForAsset(assetName, assetPath: assetpath)
            }
        }
    }
    
    private func createSceneNodeForAsset(_ assetName: String, assetPath: String) -> SCNNode? {
        guard let scene = SCNScene(named: assetPath) else {
            return nil
        }
        let node = scene.rootNode.childNode(withName: assetName, recursively: true)
        return node
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: sceneView),
                let modelName = currentModel?.fileName else {
            return
        }
        
        if let nodeExists = sceneView.scene.rootNode.childNode(withName: modelName, recursively: true) {
            nodeExists.removeFromParentNode()
        }
        
        addAnchor(using: location)
    }
    
    private func addAnchor(using location: CGPoint) {
        let hitResultsFeaturePoints: [ARHitTestResult] = sceneView.hitTest(location, types: .featurePoint)
        
        if let hit = hitResultsFeaturePoints.first {
            
            let rotate = simd_float4x4(SCNMatrix4MakeRotation(sceneView.session.currentFrame!.camera.eulerAngles.y, 0, 1, 0))
            let finalTransform = simd_mul(hit.worldTransform, rotate)
            let anchor = ARAnchor(transform: finalTransform)
            
            sceneView.session.add(anchor: anchor)
        }
    }
}

extension ViewController: ARSCNViewDelegate {
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if !anchor.isKind(of: ARPlaneAnchor.self) {
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                guard let model = strongSelf.modelNodeModel else {
                    print("We have no model to render")
                    return
                }
                
                let modelClone = model.clone()
                modelClone.position = SCNVector3Zero
                
                node.addChildNode(modelClone)
                node.addChildNode(strongSelf.lightNodeModel!)
                node.addChildNode(strongSelf.planeNodeModel!)
                                
                strongSelf.setSceneLighting()
                strongSelf.setScenePlane()
            }
        }
    }
    
    private func setSceneLighting() {
        guard let lightnode = lightNodeModel else { return }
        
        let estimate: ARLightEstimate! = sceneView.session.currentFrame?.lightEstimate
        let light: SCNLight! = lightnode.light
        
        light.intensity = currentModel?.lightSettings.intensity ?? estimate.ambientIntensity
        light.shadowMode = currentModel?.lightSettings.shadowMode
        light.shadowSampleCount = currentModel?.lightSettings.shadowSampleCount
    }
    
    private func setScenePlane() {
        guard let planenode = planeNodeModel else { return }
        
        let plane = planenode.geometry!
        
        plane.firstMaterial?.writesToDepthBuffer = currentModel?.planeSettings.writesToDepthBuffer!
        plane.firstMaterial?.colorBufferWriteMask = []
    }
}
