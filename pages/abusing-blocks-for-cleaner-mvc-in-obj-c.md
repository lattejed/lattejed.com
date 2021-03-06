---
template: post
title: "[Ab]using Blocks for Cleaner MVC in Obj-C"
date: 2014-05-26
---

As I've started to utilize blocks more in iOS/OS X development I've noticed a patter emerge and wanted to talk about it. It's using the same building blocks (excuse the pun) are you're likely to find in any Cocoa project but leveraging blocks to the fullest extent has sped up development time for me and led to both thin controllers (which I think are good) and a very strict separation between the different layers in MVC.

(Note: I wanted to point out that MVC in Cocoa in general, and explicitly in the example I give here, is more accurately called Model-View-Adapter as the model and view layers do not interact directly with one another, as they would be allowed to do in traditional MVC.)

I won't talk about blocks since they've been around for a while but if you're not familiar with Obj-C a block is an anonymous / first class function. It grants Obj-C (and C and C++) a handy tool for adopting a more functional programming style. The syntax can be awkward at first and I recommend [this site](http://fuckingblocksyntax.com/) as a handy reference and for an occasional laugh.

So what does a block have to do with MVC? In MVC the controller layer is responsible for mediating between the model and view layers and usually "owns" or manages the lifecycle of both. While in theory a controller will generally be "thin", doing no more than it has to do to tie model to view, they tend to bloat over time.

In very practical terms, controllers usually have a lot of functions defined in them. For every possible action in a view layer the controller will usually have a separate function (or a shared function with additional logic to determine the sender and action required). Working with Xcode and IB, that means defining and implementing a function as well as making a connection for that action in IB. Since we usually need a reference to the sender(s) (think a set of buttons with mutually exclusive state) we also end up defining properties. That's a lot of "stuff" for, say, an "Open File" button.

So the first step in cleaning up our controller is adding blocks to buttons that allow us to define that button's action. We can do this quite easily by using the Obj-C runtime together with a category:

```objectivec
//
//  NSButton+LJBlocks.h
//
//  Created by Matthew Smith on 4/21/14.
//  Copyright (c) 2014 LatteJed. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSButton (LJBlocks)

- (void)setActionBlock:(void (^)(void))block;

@end

//
//  NSButton+LJBlocks.m
//
//  Created by Matthew Smith on 4/21/14.
//  Copyright (c) 2014 LatteJed. All rights reserved.
//

#import "NSButton+LJBlocks.h"
#import <objc/runtime.h>

static void* const kNSButton_LJBlocks_HelperKey = (void *)&kNSButton_LJBlocks_HelperKey;

@interface __NSButtonHelper : NSObject

@property (nonatomic, weak) NSButton* owner;
@property (nonatomic, copy) void (^block)(void);

- (void)action:(id)sender;

@end

@implementation NSButton (LJBlocks)

- (void)setActionBlock:(void (^)(void))block;
{
    __NSButtonHelper* helper = [self lj_NSPopupButton_blocks_helper];
    helper.block = block;

    [self setAction:@selector(action:)];
    [self setTarget:helper];
}

- (__NSButtonHelper *)lj_NSPopupButton_blocks_helper;
{
    __NSButtonHelper* helper = objc_getAssociatedObject(self, kNSButton_LJBlocks_HelperKey);
    if (!helper)
    {
        helper = [__NSButtonHelper new];
        helper.owner = self;
        objc_setAssociatedObject(self, kNSButton_LJBlocks_HelperKey, helper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return helper;
}

@end

@implementation __NSButtonHelper

- (void)action:(id)sender;
{
    if (self.owner)
    {
        self.block();
    }
}

@end
```

This is a very useful pattern. Here we're creating a category with a single method that allows us to add a block that will get called whenever the button is pressed. Since controls in Cocoa need a target and an action (an object and a method) we use what's called a glue object (or trampoline or helper) that gets created when the block is set. To hide this from the user, we have the control retain the helper object using the runtime method `objc_setAssociatedObject`. (This is a common workaround to a category's inability to define instance variables.)

What this means in practice is that we can minimize the "glue" we need to connect our button to our controller. Instead of defining a method and a property we can simply define a property. Instead of spreading out our logic through the controller, we can define our method anonymously in an appropriate initialization method (most likely `awakeFromNib`).

To complement this functional controller style I tend to post notifications from the model and then set up observers in the controller also using blocks. This is much easier to show than explain. Here is our model:

```objectivec
//
//  Model.h
//
//  Created by Matthew Smith on 5/21/14.
//  Copyright (c) 2014 LatteJed. All rights reserved.
//

static NSString* const kNotificationURLDidUpdate = @"kNotificationURLDidUpdate";

@interface Model : NSObject

@property (nonatomic, copy) NSURL* url;

@end

//
//  Model.m
//
//  Created by Matthew Smith on 5/21/14.
//  Copyright (c) 2014 LatteJed. All rights reserved.
//

#import "Model.h"

@implementation Model

- (void)setUrl:(NSURL *)url;
{
    _url = url;
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationURLDidUpdate
                                                        object:self];
}

@end
```

This is simplified to only contain one property, the url of some file. We use a custom setter to post a notification after a url has been set. Our controller would then look like this:

```objectivec
//
//  Controller.m
//
//  Created by Matthew Smith on 4/21/14.
//  Copyright (c) 2014 LatteJed. All rights reserved.
//

#import "Controller.h"
#import "Model.h"

@interface Controller ()

@property (nonatomic, weak) IBOutlet NSButton* openFileButton;
@property (nonatomic, weak) IBOutlet FileView* fileView;
@property (nonatomic, strong) Model* model;

@end

@implementation Controller

- (void)awakeFromNib;
{
    [self.openFileButton setActionBlock:^{
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel beginSheetModalForWindow:[[self view] window]
                      completionHandler:^(NSInteger result) {
                          if (result == NSFileHandlingPanelOKButton)
                          {
                              self.model = [Model new];
                              self.model.url = [[panel URLs] firstObject];
                          }
                      }];
    }];

    [[NSNotificationCenter defaultCenter]
              addObserverForName:kNotificationURLDidUpdate
                          object:nil
                           queue:nil
                      usingBlock:^(NSNotification *note) {
                          if ([self.model url])
                          {
                              [self.fileView setFileWithURL:self.model.url];
                          }
                      }];
}
```

You can see that the entire MVC relationship here is defined by two blocks: the block provided by the button that gets called when it's pressed, which updates the model (in this case after the file dialog returns successfully), and the block provided by the notification observer. Although it would be possible to "short cut" the update to the view by having the controller update the view directly, I find this to be conceptually much cleaner and makes situations where the model is driving (and not user interaction) easier to deal with. Again, this also saves us from having to define additional methods on the controller, which means less typing.

While a trivial example like this seems, well, trivial, if we add in a set of buttons (say zoom in and zoom out buttons) we now have to deal with lots of additional logic and edge cases for what should be a simple operation. We can have the model define an initial zoom level when it's created and cascade that to the controller (where we can disable/enable buttons appropriately) and view. We can have the controller validate input (can we zoom in any further?) and have a single point of action for everything we need to do.

This is pretty simple, so why bother?

I think this is valuable for a number of reasons. It lends conceptual consistency for how a controller operates -- everything cascades from the model and everything is handled in an anonymous function -- the controller is simpler and its role of "mediating" more clearly defined. I also find that it makes it harder to break the rules of MVC (something I do occasionally even though I have quite a bit of experience) which saves refactoring time later.

Another reason is that although controllers should be thin logically, in practice they end up handling a lot of interaction between the view and model layers, which means they end up bloated with dozens of methods, `#pragma mark -` sections, delegate method implementations, etc. Using primarily anonymous functions for this mediation makes controller code more succinct and manageable.
