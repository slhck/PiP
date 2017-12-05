#import "openGLView.h"
#import <GLUT/glut.h>
#import <OpenGL/OpenGL.h>
#import <QuartzCore/QuartzCore.h>

@implementation OpenGLView

- (id)initWithFrame:(NSRect)frameRect rightCLickDelegate:(id<RightCLickDelegate>) delegate{

    NSOpenGLPixelFormatAttribute   attribsAntialised[] = {
        NSOpenGLPFAAccelerated,
        NSOpenGLPFANoRecovery,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFAAlphaSize,  8,
        NSOpenGLPFAMultisample,
        NSOpenGLPFASampleBuffers, 1,
        NSOpenGLPFASamples, 4,
        0,
    };

    NSOpenGLPixelFormatAttribute   attribsBasic[] = {
        NSOpenGLPFAAccelerated,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFAAlphaSize,  8,
        0,
    };
    
    NSOpenGLPixelFormat *_pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribsAntialised];
    
    if (nil == _pixelFormat) {
        NSLog(@"Couldn't find an FSAA pixel format, trying something more basic");
        _pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribsBasic];
    }
    
    self = [super initWithFrame:frameRect pixelFormat:_pixelFormat];
    
    pixelFormat = _pixelFormat;
    
    if (self) {
        int VBL = 1;
        [[self openGLContext] setValues:&VBL forParameter:NSOpenGLCPSwapInterval];
    }
    
    alreadyCropped = false;
    imageRect = CGRectMake(0,0,200,200);
    imageAspectRatio = 0;
    rightCLickDelegate = delegate;
    
    return self;
}


// Create CIContext based on OpenGL context and pixel format
- (BOOL)createCIContext{
    
    
    // Create CIContext from the OpenGL context.
    myCIcontext = [CIContext contextWithCGLContext:[[self openGLContext] CGLContextObj] pixelFormat:[pixelFormat CGLPixelFormatObj] colorSpace: nil options: nil];

    if (!myCIcontext){
        NSLog(@"CIContext creation failed");
        return NO;
    }
    
    // Created succesfully
    return YES;
}

// Create or update the hardware accelerated offscreen area
// Framebuffer object aka. FBO
- (void)setFBO{
    
    // If not previously setup
    // generate IDs for FBO and its associated texture
    if (!FBOid){
        // Make sure the framebuffer extenstion is supported
        const GLubyte* strExt;
        GLboolean isFBO;
        // Get the extenstion name string.
        // It is a space-delimited list of the OpenGL extenstions
        // that are supported by the current renderer
        strExt = glGetString(GL_EXTENSIONS);
        isFBO = gluCheckExtension((const GLubyte*)"GL_EXT_framebuffer_object", strExt);
        if (!isFBO)
            NSLog(@"Your system does not support framebuffer extension");
        
        // create FBO object
        glGenFramebuffersEXT(1, &FBOid);
        // the texture
        glGenTextures(1, &FBOTextureId);
    }
    
    // Bind to FBO
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, FBOid);
    
    // Sanity check against maximum OpenGL texture size
    // If bigger adjust to maximum possible size
    // while maintain the aspect ratio
    GLint maxTexSize;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTexSize);
    if (imageRect.size.width > maxTexSize || imageRect.size.height > maxTexSize){
        if (imageAspectRatio > 1){
            imageRect.size.width = maxTexSize;
            imageRect.size.height = maxTexSize / imageAspectRatio;
        }
        else{
            imageRect.size.width = maxTexSize * imageAspectRatio ;
            imageRect.size.height = maxTexSize;
        }
    }
    
    // Initialize FBO Texture
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, FBOTextureId);

    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA, imageRect.size.width, imageRect.size.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
    
    // and attach texture to the FBO as its color destination
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, FBOTextureId, 0);
 
    // Make sure the FBO was created succesfully.
    if (GL_FRAMEBUFFER_COMPLETE_EXT != glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT))
        NSLog(@"Framebuffer Object creation or update failed!");
    
    // unbind FBO
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
}

- (void)prepareOpenGL{
    glClearColor(255.0f, 255.0f, 255.0f, 255.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glEnable(GL_TEXTURE_RECTANGLE_ARB);
    [self createCIContext];
}

- (void) renderScene{
    if(!imageAspectRatio) return;
    NSRect bounds = [self bounds];
    float screenAspectRatio = bounds.size.width / bounds.size.height;
    float arr = imageAspectRatio / screenAspectRatio;
    
    if( 0.99 > arr || arr > 1.01){
//        NSLog(@"set ar");
        [self.window setContentSize:NSMakeSize(bounds.size.width, bounds.size.width / imageAspectRatio)];
        [self.window setAspectRatio:imageRect.size];
    }

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glViewport(0, 0, bounds.size.width, bounds.size.height);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();

    glMatrixMode(GL_TEXTURE);
    glLoadIdentity();

    glScalef(imageRect.size.width, imageRect.size.height, 1.0f);

    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();

    glDisable(GL_BLEND);

    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, FBOTextureId);
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    glPushMatrix();

    glBegin(GL_QUADS);
    glTexCoord2f(0, 0); glVertex2f(-1.0f, -1.0f);
    glTexCoord2f(1, 0); glVertex2f(1.0f, -1.0f);
    glTexCoord2f(1, 1); glVertex2f(1.0f, 1.0f);
    glTexCoord2f(0, 1); glVertex2f(-1.0f, 1.0f);

    glEnd();
    glPopMatrix();
}

-(void) drawRect: (NSRect) bounds{
    [[self openGLContext] makeCurrentContext];
    [self renderScene];
    [[self openGLContext] flushBuffer];
}

-(BOOL) isOpaque{
    return NO;
}

- (void) drawImage: (CGImageRef) cgimage withRect:(CGRect) rect{
    myCIImage = [CIImage imageWithCGImage:cgimage];
    
    CGRect imgRect = [myCIImage extent];

    if(rect.size.width == 0){
        imageRect = imgRect;
        alreadyCropped = false;
    }
    else if(!alreadyCropped){
        alreadyCropped = true;
        CGRect bounds = [self bounds];
        float scale = imgRect.size.width / bounds.size.width;
        imageRect = CGRectMake(rect.origin.x * scale, rect.origin.y * scale, rect.size.width * scale, rect.size.height * scale);
    }
    
    imageAspectRatio = imageRect.size.width / imageRect.size.height;

    [self setFBO];

    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, FBOid);

    GLint width = (GLint)ceil(imageRect.size.width);
    GLint height = (GLint)ceil(imageRect.size.height);

    glViewport(0, 0, width, height);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, width, 0, height, -1, 1);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    [myCIcontext drawImage: myCIImage atPoint: CGPointZero  fromRect: imageRect];

    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
    
    [self setNeedsDisplay:YES];
}

- (void)rightMouseDown:(NSEvent *)theEvent {
    [rightCLickDelegate rightMouseDown:theEvent];
}

@end
