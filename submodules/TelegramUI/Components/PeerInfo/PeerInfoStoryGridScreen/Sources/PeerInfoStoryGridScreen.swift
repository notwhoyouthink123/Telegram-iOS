import Foundation
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import ComponentFlow
import TelegramCore
import PeerInfoVisualMediaPaneNode
import ViewControllerComponent
import ChatListHeaderComponent
import ContextUI
import ChatTitleView
import BottomButtonPanelComponent
import UndoUI
import MoreHeaderButton

final class PeerInfoStoryGridScreenComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment
    
    let context: AccountContext
    let peerId: EnginePeer.Id
    let scope: PeerInfoStoryGridScreen.Scope

    init(
        context: AccountContext,
        peerId: EnginePeer.Id,
        scope: PeerInfoStoryGridScreen.Scope
    ) {
        self.context = context
        self.peerId = peerId
        self.scope = scope
    }

    static func ==(lhs: PeerInfoStoryGridScreenComponent, rhs: PeerInfoStoryGridScreenComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.peerId != rhs.peerId {
            return false
        }
        if lhs.scope != rhs.scope {
            return false
        }

        return true
    }
    
    final class View: UIView {
        private var component: PeerInfoStoryGridScreenComponent?
        private weak var state: EmptyComponentState?
        private var environment: EnvironmentType?
        
        private var paneNode: PeerInfoStoryPaneNode?
        private var paneStatusDisposable: Disposable?
        private(set) var paneStatusText: String?
        
        private(set) var selectedCount: Int = 0
        private var selectionStateDisposable: Disposable?
        
        private var selectionPanel: ComponentView<Empty>?
        
        private weak var mediaGalleryContextMenu: ContextController?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        deinit {
            self.paneStatusDisposable?.dispose()
            self.selectionStateDisposable?.dispose()
        }
        
        func morePressed(source: ContextReferenceContentNode) {
            guard let component = self.component, let controller = self.environment?.controller(), let pane = self.paneNode else {
                return
            }

            var items: [ContextMenuItem] = []
            
            let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
            let strings = presentationData.strings
            
            if self.selectedCount != 0 {
                //TODO:localize
                //TODO:update icon
                items.append(.action(ContextMenuActionItem(text: "Save to Photos", icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Save"), color: theme.contextMenu.primaryColor)
                }, action: { [weak self] _, a in
                    a(.default)
                    
                    guard let self, let component = self.component else {
                        return
                    }
                    
                    let _ = component
                })))
                items.append(.action(ContextMenuActionItem(text: strings.Common_Delete, textColor: .destructive, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor)
                }, action: { [weak self] _, a in
                    a(.default)
                    
                    guard let self, let component = self.component, let environment = self.environment else {
                        return
                    }
                    guard let paneNode = self.paneNode, !paneNode.selectedIds.isEmpty else {
                        return
                    }
                    let _ = component.context.engine.messages.deleteStories(ids: Array(paneNode.selectedIds)).start()
                    
                    //TODO:localize
                    let text: String
                    if paneNode.selectedIds.count == 1 {
                        text = "1 story deleted."
                    } else {
                        text = "\(paneNode.selectedIds.count) stories deleted."
                    }
                    
                    let presentationData = component.context.sharedContext.currentPresentationData.with({ $0 }).withUpdated(theme: environment.theme)
                    environment.controller()?.present(UndoOverlayController(
                        presentationData: presentationData,
                        content: .info(title: nil, text: text, timeout: nil),
                        elevatedLayout: false,
                        animateInAsReplacement: false,
                        action: { _ in return false }
                    ), in: .current)
                    
                    paneNode.clearSelection()
                })))
            } else {
                var recurseGenerateAction: ((Bool) -> ContextMenuActionItem)?
                let generateAction: (Bool) -> ContextMenuActionItem = { [weak pane] isZoomIn in
                    let nextZoomLevel = isZoomIn ? pane?.availableZoomLevels().increment : pane?.availableZoomLevels().decrement
                    let canZoom: Bool = nextZoomLevel != nil
                    
                    return ContextMenuActionItem(id: isZoomIn ? 0 : 1, text: isZoomIn ? strings.SharedMedia_ZoomIn : strings.SharedMedia_ZoomOut, textColor: canZoom ? .primary : .disabled, icon: { theme in
                        return generateTintedImage(image: UIImage(bundleImageName: isZoomIn ? "Chat/Context Menu/ZoomIn" : "Chat/Context Menu/ZoomOut"), color: canZoom ? theme.contextMenu.primaryColor : theme.contextMenu.primaryColor.withMultipliedAlpha(0.4))
                    }, action: canZoom ? { action in
                        guard let pane = pane, let zoomLevel = isZoomIn ? pane.availableZoomLevels().increment : pane.availableZoomLevels().decrement else {
                            return
                        }
                        pane.updateZoomLevel(level: zoomLevel)
                        if let recurseGenerateAction = recurseGenerateAction {
                            action.updateAction(0, recurseGenerateAction(true))
                            action.updateAction(1, recurseGenerateAction(false))
                        }
                    } : nil)
                }
                recurseGenerateAction = { isZoomIn in
                    return generateAction(isZoomIn)
                }
                
                items.append(.action(generateAction(true)))
                items.append(.action(generateAction(false)))
                
                if component.peerId == component.context.account.peerId, case .saved = component.scope {
                    var ignoreNextActions = false
                    //TODO:localize
                    items.append(.action(ContextMenuActionItem(text: "Show Archive", icon: { theme in
                        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/StoryArchive"), color: theme.contextMenu.primaryColor)
                    }, action: { [weak self] _, a in
                        if ignoreNextActions {
                            return
                        }
                        ignoreNextActions = true
                        a(.default)
                        
                        guard let self, let component = self.component else {
                            return
                        }
                        
                        self.environment?.controller()?.push(PeerInfoStoryGridScreen(context: component.context, peerId: component.peerId, scope: .archive))
                    })))
                }
                
                /*if photoCount != 0 && videoCount != 0 {
                 items.append(.separator)
                 
                 let showPhotos: Bool
                 switch pane.contentType {
                 case .photo, .photoOrVideo:
                 showPhotos = true
                 default:
                 showPhotos = false
                 }
                 let showVideos: Bool
                 switch pane.contentType {
                 case .video, .photoOrVideo:
                 showVideos = true
                 default:
                 showVideos = false
                 }
                 
                 items.append(.action(ContextMenuActionItem(text: strings.SharedMedia_ShowPhotos, icon: { theme in
                 if !showPhotos {
                 return nil
                 }
                 return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor)
                 }, action: { [weak pane] _, a in
                 a(.default)
                 
                 guard let pane = pane else {
                 return
                 }
                 let updatedContentType: PeerInfoVisualMediaPaneNode.ContentType
                 switch pane.contentType {
                 case .photoOrVideo:
                 updatedContentType = .video
                 case .photo:
                 updatedContentType = .photo
                 case .video:
                 updatedContentType = .photoOrVideo
                 default:
                 updatedContentType = pane.contentType
                 }
                 pane.updateContentType(contentType: updatedContentType)
                 })))
                 items.append(.action(ContextMenuActionItem(text: strings.SharedMedia_ShowVideos, icon: { theme in
                 if !showVideos {
                 return nil
                 }
                 return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor)
                 }, action: { [weak pane] _, a in
                 a(.default)
                 
                 guard let pane = pane else {
                 return
                 }
                 let updatedContentType: PeerInfoVisualMediaPaneNode.ContentType
                 switch pane.contentType {
                 case .photoOrVideo:
                 updatedContentType = .photo
                 case .photo:
                 updatedContentType = .photoOrVideo
                 case .video:
                 updatedContentType = .video
                 default:
                 updatedContentType = pane.contentType
                 }
                 pane.updateContentType(contentType: updatedContentType)
                 })))
                 }*/
            }

            let contextController = ContextController(account: component.context.account, presentationData: presentationData, source: .reference(PeerInfoContextReferenceContentSource(controller: controller, sourceNode: source)), items: .single(ContextController.Items(content: .list(items))), gesture: nil)
            contextController.passthroughTouchEvent = { [weak self] sourceView, point in
                guard let self else {
                    return .ignore
                }

                let localPoint = self.convert(sourceView.convert(point, to: nil), from: nil)
                guard let localResult = self.hitTest(localPoint, with: nil) else {
                    return .dismiss(consume: true, result: nil)
                }

                var testView: UIView? = localResult
                while true {
                    if let testViewValue = testView {
                        if let node = testViewValue.asyncdisplaykit_node as? PeerInfoStoryPaneNode {
                            node.brieflyDisableTouchActions()
                            return .dismiss(consume: false, result: nil)
                        } else {
                            testView = testViewValue.superview
                        }
                    } else {
                        break
                    }
                }

                return .dismiss(consume: true, result: nil)
            }
            self.mediaGalleryContextMenu = contextController
            controller.presentInGlobalOverlay(contextController)
        }
        
        func update(component: PeerInfoStoryGridScreenComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: Transition) -> CGSize {
            self.component = component
            self.state = state
            
            let sideInset: CGFloat = 14.0
            
            let environment = environment[EnvironmentType.self].value
            
            let themeUpdated = self.environment?.theme !== environment.theme
            
            self.environment = environment
            
            if themeUpdated {
                self.backgroundColor = environment.theme.list.plainBackgroundColor
            }
            
            var bottomInset: CGFloat = environment.safeInsets.bottom
            
            if self.selectedCount != 0 {
                let selectionPanel: ComponentView<Empty>
                var selectionPanelTransition = transition
                if let current = self.selectionPanel {
                    selectionPanel = current
                } else {
                    selectionPanelTransition = .immediate
                    selectionPanel = ComponentView()
                    self.selectionPanel = selectionPanel
                }
                
                //TODO:localize
                let selectionPanelSize = selectionPanel.update(
                    transition: selectionPanelTransition,
                    component: AnyComponent(BottomButtonPanelComponent(
                        theme: environment.theme,
                        title: "Save to Profile",
                        label: nil,
                        isEnabled: true,
                        insets: UIEdgeInsets(top: 0.0, left: sideInset, bottom: environment.safeInsets.bottom, right: sideInset),
                        action: { [weak self] in
                            guard let self, let component = self.component, let environment = self.environment else {
                                return
                            }
                            guard let paneNode = self.paneNode, !paneNode.selectedIds.isEmpty else {
                                return
                            }
                            
                            let _ = component.context.engine.messages.updateStoriesArePinned(ids: paneNode.selectedItems, isPinned: true).start()
                            
                            //TODO:localize
                            let title: String
                            if paneNode.selectedIds.count == 1 {
                                title = "Story saved to your profile"
                            } else {
                                title = "\(paneNode.selectedIds.count) saved to your profile"
                            }
                            
                            let presentationData = component.context.sharedContext.currentPresentationData.with({ $0 }).withUpdated(theme: environment.theme)
                            environment.controller()?.present(UndoOverlayController(
                                presentationData: presentationData,
                                content: .info(title: title, text: "Saved stories can be viewed by others on your profile until you remove them.", timeout: nil),
                                elevatedLayout: false,
                                animateInAsReplacement: false,
                                action: { _ in return false }
                            ), in: .current)
                            
                            paneNode.clearSelection()
                        }
                    )),
                    environment: {},
                    containerSize: availableSize
                )
                if let selectionPanelView = selectionPanel.view {
                    var animateIn = false
                    if selectionPanelView.superview == nil {
                        self.addSubview(selectionPanelView)
                        animateIn = true
                    }
                    selectionPanelTransition.setFrame(view: selectionPanelView, frame: CGRect(origin: CGPoint(x: 0.0, y: availableSize.height - selectionPanelSize.height), size: selectionPanelSize))
                    if animateIn {
                        transition.animatePosition(view: selectionPanelView, from: CGPoint(x: 0.0, y: selectionPanelSize.height), to: CGPoint(), additive: true)
                    }
                }
                bottomInset = selectionPanelSize.height
            } else if let selectionPanel = self.selectionPanel {
                self.selectionPanel = nil
                if let selectionPanelView = selectionPanel.view {
                    transition.setPosition(view: selectionPanelView, position: CGPoint(x: selectionPanelView.center.x, y: availableSize.height + selectionPanelView.bounds.height * 0.5), completion: { [weak selectionPanelView] _ in
                        selectionPanelView?.removeFromSuperview()
                    })
                }
            }
            
            let paneNode: PeerInfoStoryPaneNode
            if let current = self.paneNode {
                paneNode = current
            } else {
                paneNode = PeerInfoStoryPaneNode(
                    context: component.context,
                    peerId: component.peerId,
                    chatLocation: .peer(id: component.peerId),
                    contentType: .photoOrVideo,
                    captureProtected: false,
                    isSaved: true,
                    isArchive: component.scope == .archive,
                    navigationController: { [weak self] in
                        guard let self else {
                            return nil
                        }
                        return self.environment?.controller()?.navigationController as? NavigationController
                    }
                )
                self.paneNode = paneNode
                self.addSubview(paneNode.view)
                
                self.paneStatusDisposable = (paneNode.status
                |> deliverOnMainQueue).start(next: { [weak self] status in
                    guard let self else {
                        return
                    }
                    if self.paneStatusText != status?.text {
                        self.paneStatusText = status?.text
                        (self.environment?.controller() as? PeerInfoStoryGridScreen)?.updateTitle()
                    }
                })
                
                var applyState = false
                self.selectionStateDisposable = (paneNode.updatedSelectedIds
                |> distinctUntilChanged
                |> deliverOnMainQueue).start(next: { [weak self] selectedIds in
                    guard let self else {
                        return
                    }
                    
                    self.selectedCount = selectedIds.count
                    
                    if applyState {
                        self.state?.updated(transition: Transition(animation: .curve(duration: 0.4, curve: .spring)))
                    }
                    (self.environment?.controller() as? PeerInfoStoryGridScreen)?.updateTitle()
                })
                applyState = true
            }
            
            paneNode.update(
                size: availableSize,
                topInset: environment.navigationHeight,
                sideInset: environment.safeInsets.left,
                bottomInset: bottomInset,
                visibleHeight: availableSize.height,
                isScrollingLockedAtTop: false,
                expandProgress: 1.0,
                presentationData: component.context.sharedContext.currentPresentationData.with({ $0 }),
                synchronous: false,
                transition: transition.containedViewLayoutTransition
            )
            transition.setFrame(view: paneNode.view, frame: CGRect(origin: CGPoint(), size: availableSize))
            
            return availableSize
        }
    }
    
    func makeView() -> View {
        return View()
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

public class PeerInfoStoryGridScreen: ViewControllerComponentContainer {
    public enum Scope {
        case saved
        case archive
    }
    
    private let context: AccountContext
    private let scope: Scope
    private var isDismissed: Bool = false
    
    private var titleView: ChatTitleView?
    
    private var moreBarButton: MoreHeaderButton?
    private var moreBarButtonItem: UIBarButtonItem?
    
    public init(
        context: AccountContext,
        peerId: EnginePeer.Id,
        scope: Scope
    ) {
        self.context = context
        self.scope = scope
        
        super.init(context: context, component: PeerInfoStoryGridScreenComponent(
            context: context,
            peerId: peerId,
            scope: scope
        ), navigationBarAppearance: .default, theme: .default)
        
        let presentationData = context.sharedContext.currentPresentationData.with({ $0 })
        let moreBarButton = MoreHeaderButton(color: presentationData.theme.rootController.navigationBar.buttonColor)
        moreBarButton.isUserInteractionEnabled = true
        self.moreBarButton = moreBarButton
        
        moreBarButton.setContent(.more(MoreHeaderButton.optionsCircleImage(color: presentationData.theme.rootController.navigationBar.buttonColor)))
        let moreBarButtonItem = UIBarButtonItem(customDisplayNode: self.moreBarButton)!
        self.moreBarButtonItem = moreBarButtonItem
        moreBarButton.contextAction = { [weak self] sourceNode, gesture in
            guard let self else {
                return
            }
            let _ = self
        }
        moreBarButton.addTarget(self, action: #selector(self.morePressed), forControlEvents: .touchUpInside)
        
        self.navigationItem.setRightBarButton(moreBarButtonItem, animated: false)
        
        self.titleView = ChatTitleView(
            context: context, theme:
                presentationData.theme,
            strings: presentationData.strings,
            dateTimeFormat: presentationData.dateTimeFormat,
            nameDisplayOrder: presentationData.nameDisplayOrder,
            animationCache: context.animationCache,
            animationRenderer: context.animationRenderer
        )
        self.titleView?.disableAnimations = true
        
        self.navigationItem.titleView = self.titleView
        
        self.updateTitle()
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
    }
    
    func updateTitle() {
        //TODO:localize
        switch self.scope {
        case .saved:
            guard let componentView = self.node.hostView.componentView as? PeerInfoStoryGridScreenComponent.View else {
                return
            }
            let title: String?
            if let paneStatusText = componentView.paneStatusText, !paneStatusText.isEmpty {
                title = paneStatusText
            } else {
                title = nil
            }
            self.titleView?.titleContent = .custom("My Stories", title, false)
        case .archive:
            guard let componentView = self.node.hostView.componentView as? PeerInfoStoryGridScreenComponent.View else {
                return
            }
            let title: String
            if componentView.selectedCount != 0 {
                title = "\(componentView.selectedCount) Selected"
            } else {
                title = "Stories Archive"
            }
            self.titleView?.titleContent = .custom(title, nil, false)
        }
    }
    
    @objc private func morePressed() {
        guard let componentView = self.node.hostView.componentView as? PeerInfoStoryGridScreenComponent.View else {
            return
        }
        guard let moreBarButton = self.moreBarButton else {
            return
        }
        componentView.morePressed(source: moreBarButton.referenceNode)
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.titleView?.layout = layout
    }
}

private final class PeerInfoContextReferenceContentSource: ContextReferenceContentSource {
    private let controller: ViewController
    private let sourceNode: ContextReferenceContentNode
    
    init(controller: ViewController, sourceNode: ContextReferenceContentNode) {
        self.controller = controller
        self.sourceNode = sourceNode
    }
    
    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.sourceNode.view, contentAreaInScreenSpace: UIScreen.main.bounds)
    }
}
