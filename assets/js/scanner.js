const ZXing = window.ZXing;

window.scannerState = {
    codeReader: null,
    videoElement: null,
    stream: null,
    onDetectCallback: null,
    onErrorCallback: null,
    videoContainerId: null,
    viewId: null,
};

async function waitForElement(selector, timeout = 5000) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
        const element = document.getElementById(selector);
        if (element) return element;
        await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error(`Timeout waiting for element: ${selector}`);
}

async function getVideoInputDevices() {
    console.log("[JS] getVideoInputDevices called");
    try {

        await navigator.mediaDevices.getUserMedia({ video: true, audio: false })
            .then(stream => {
                stream.getTracks().forEach(track => track.stop());
                console.log("[JS] Temporary stream acquired for permissions check.");
            }).catch(err => {
                console.warn("[JS] Error acquiring temp stream (permissions?):", err.name);
            });


        const devices = await navigator.mediaDevices.enumerateDevices();
        const videoDevices = devices.filter(device => device.kind === 'videoinput');

        console.log("[JS] Found video devices:", videoDevices);
        return videoDevices.map(device => ({
            deviceId: device.deviceId,
            label: device.label || `Camera ${videoDevices.indexOf(device) + 1}`
        }));
    } catch (error) {
        console.error('[JS] Error enumerating devices:', error);
        return [];
    }
}


async function startCamera(videoContainerId, viewId, deviceId, onDetect, onError) {
    console.log(`[JS] startCamera called for viewId: ${viewId}, deviceId: ${deviceId || 'Default'}`);
    window.scannerState.onDetectCallback = onDetect;
    window.scannerState.onErrorCallback = onError;
    window.scannerState.videoContainerId = videoContainerId;
    window.scannerState.viewId = viewId;

    if (!ZXing) {
        console.error("[JS] ZXing library not loaded!");
        if (window.scannerState.onErrorCallback) {
            window.scannerState.onErrorCallback("ZXing library not loaded");
        }
        return;
    }

    if (window.scannerState.codeReader && window.scannerState.viewId === viewId) {
        console.warn(`[JS] Scanner already running for viewId: ${viewId}. Restarting.`);
        await stopCamera(viewId);
    }

    window.scannerState.codeReader = new ZXing.BrowserMultiFormatReader();

    const videoContainer = await waitForElement(videoContainerId);
    if (!videoContainer) {
        console.error(`[JS] Video container not found: ${videoContainerId}`);
        if (window.scannerState.onErrorCallback) {
            window.scannerState.onErrorCallback(`Video container not found: ${videoContainerId}`);
        }
        return;
    }

    const videoElement = document.createElement('video');
    videoElement.id = `video-${viewId}`;
    videoElement.style.width = '100%';
    videoElement.style.height = '100%';
    videoElement.style.objectFit = 'cover';
    videoElement.setAttribute('playsinline', '');
    videoContainer.appendChild(videoElement);
    window.scannerState.videoElement = videoElement;

    console.log(`[JS] Starting scan for video element: ${videoElement.id}`);

    try {
        let constraints;
        if (deviceId && deviceId.length > 0) {
            console.log(`[JS] Using specific deviceId: ${deviceId}`);
            constraints = {
                video: {
                    deviceId: { exact: deviceId }
                }
            };
        } else {
            console.log("[JS] No specific deviceId provided, using default facingMode.");
            constraints = {
                video: { facingMode: 'environment' }
            };
        }

        window.scannerState.stream = await navigator.mediaDevices.getUserMedia(constraints);
        window.scannerState.codeReader.decodeFromStream(window.scannerState.stream, videoElement, (result, err) => {
            if (result) {
                console.log("[JS] Code detected:", result.getText());
                if (window.scannerState.onDetectCallback) {
                    window.scannerState.onDetectCallback(result.getText(), result.getBarcodeFormat().toString());
                }
            }
            if (err && !(err instanceof ZXing.NotFoundException)) {
                console.error('[JS] Decode Error:', err);
                if (window.scannerState.onErrorCallback) {
                    window.scannerState.onErrorCallback(`Decode Error: ${err.message}`);
                }
            }
        });

        console.log(`[JS] Scan started successfully for viewId: ${viewId}`);

    } catch (error) {
        console.error('[JS] Camera Access or Start Error:', error);
        let errorMessage = "Unknown camera error";
        if (error.name === 'NotAllowedError') {
            errorMessage = 'Camera permission denied. Please grant permission in your browser settings.';
        } else if (error.name === 'NotFoundError' || error.name === 'DevicesNotFoundError') {
            errorMessage = 'No suitable camera found.';
        } else if (error.name === 'NotReadableError' || error.name === 'TrackStartError') {
            errorMessage = 'Camera might be already in use by another application.';
        } else if (error instanceof DOMException) {
            errorMessage = `Camera error: ${error.message} (${error.name})`;
        } else {
            errorMessage = `Failed to start camera: ${error}`;
        }

        if (window.scannerState.onErrorCallback) {
            window.scannerState.onErrorCallback(errorMessage);
        }
        await stopCamera(viewId);
    }
}

async function stopCamera(viewId) {
    console.log(`[JS] stopCamera called for viewId: ${viewId}`);

    // if (window.scannerState.viewId !== viewId) {
    //     console.warn(`[JS] Stop request for viewId ${viewId}, but current viewId is ${window.scannerState.viewId}. Ignoring.`);
    //     return;
    // }

    if (window.scannerState.codeReader) {
        try {
            window.scannerState.codeReader.reset();
            console.log("[JS] ZXing reader reset.");
        } catch (e) {
            console.error("[JS] Error resetting ZXing reader:", e);
        }
        window.scannerState.codeReader = null;
    }

    if (window.scannerState.stream) {
        try {
            window.scannerState.stream.getTracks().forEach(track => track.stop());
            console.log("[JS] MediaStream tracks stopped.");
        } catch (e) {
            console.error("[JS] Error stopping MediaStream tracks:", e);
        }
        window.scannerState.stream = null;
    }

    if (window.scannerState.videoElement) {
        if (window.scannerState.videoElement.parentNode) {
            window.scannerState.videoElement.parentNode.removeChild(window.scannerState.videoElement);
            console.log("[JS] Video element removed from DOM.");
        } else {
            console.warn("[JS] Video element parent node not found during cleanup.");
        }
        window.scannerState.videoElement = null;
    } else {
        console.log("[JS] No video element found to remove.");
    }

    window.scannerState.onDetectCallback = null;
    window.scannerState.onErrorCallback = null;
    window.scannerState.videoContainerId = null;
    window.scannerState.viewId = null;
    console.log(`[JS] Scanner stopped and cleaned up for viewId: ${viewId}`);
}