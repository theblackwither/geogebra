/*
 * GeoGebra - Dynamic Mathematics for Everyone
 * Copyright (c) GeoGebra GmbH, Altenbergerstr. 69, 4040 Linz, Austria
 * https://www.geogebra.org
 *
 * This file is licensed under the EUPL 1.2 licence.
 * See https://www.geogebra.org/license for full licensing details.
 */

package org.geogebra.web.html5.bridge;

import org.geogebra.gwtutil.JsRunnable;

import jsinterop.annotations.JsPackage;
import jsinterop.annotations.JsProperty;
import jsinterop.annotations.JsType;

/** Optional exam lifecycle integration supplied by the iOS host. */
@JsType(isNative = true, namespace = JsPackage.GLOBAL, name = "Object")
public class IOSExamBridge {

	@JsProperty(namespace = JsPackage.GLOBAL, name = "GeoGebraIOSExamBridge")
	public static native IOSExamBridge get();

	public native boolean canStart();

	public native void stateChanged(String state);

	public native double resumeStartTime();

	public native void checkpointMeta(double startTime, String examType);

	public native void setInterruptionHandler(JsRunnable callback);
}
