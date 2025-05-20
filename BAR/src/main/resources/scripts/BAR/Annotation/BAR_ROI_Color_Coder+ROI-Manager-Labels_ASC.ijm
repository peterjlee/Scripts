/*	Fork of ROI_Color_Coder.ijm IJ BAR: https://github.com/tferr/Scripts#scripts
	https://imagej.net/doku.php?id=macro:roi_color_coder
	Colorizes ROIs by matching LUT indexes to measurements in the Results table.
	Based on the original by Tiago Ferreira, v.5.4 2017.03.10
	Peter J. Lee Applied Superconductivity Center, NHMFL
	Full history at the bottom of the file.
	v230414b-v230420:	Formatting simplified, "raised" and "recessed" replace inner shadow, major preferences added.
	f1:	updates stripKnownExtensionFromString function.
	v230517b:	Keeps focus in selected image for coloring.
	v230518:	Fixed for missing ramp issue caused by spaces in image title. Reorganized unit choices.
	v230523:	Cropped combination functionality restored. f1:	updated function stripKnownExtensionFromString f2:	updated function guessBGMedianIntensity.
	v230803:	Replaced getDir for 1.54g10.
	v230822:	Corrected selectImage to selectWindow. Removes duplicates from image list. f1:	Updated function removeDuplicatesInArray.
	v230823:	Guesses appropriate legend range and major intervals. Fixed prefs set error that opened console. Added more saved prefs.
	v230824-5:	Added 'rangeFinder' function. Colors added dialogs to highlight instructions vs. info. vs. warnings. v230825b:	Simplified output options. f1:	Updates indexOf functions.
	v230905:	Tweaked range-finding and updated functions. F1-2:	Updated getColorArrayFromColorName_v230908.
	v230911-15b:	Restricted LUT range to be within ramp range. Add unit separator options.
	v230916:	Most parameters now saved in user prefs. Streamlined trailing zeros detection for legend.
	v230921:	'Holes' option removed:	Composite ROIs preferred. Some cosmetic improvements to menu layouts.
	v231004:	Removed parenthesis in wrong place on line 1720.
	v231005:	Suggests optimum tick count. Minor tick length corrected. Added more saved prefs.
	v231006:	Can examine a subset of ROIs.
	v231009:	If there is a rectangular selection there will be an option to just examine the ROIs enclosed by the selection. Fixed DP issue with summary.
	v231011:	Expands selection types that can be used to select ROIs. Adds the selected ROI list to the summary file. If a subset is used all ROI properties are cleared first.
	v231012:	Saves ROI subset as Zip and CSV files and adds time stamps to filenames. Can import roi csv list as selection.
	v231017:	Just added more descriptions in the main dialog. Testing another minor tick number formula. v231103:	Removed redundant defGap line.
	v231129:	Added option to recall previously used bounds for crop area.
	v231130:	Just added a hint on how to handle rejected column names. b:	Reorganized ROI restriction options. F1 :	Replaced function:	pad.
	v231211:	Adds an option to measure ROIs if there are no Results.
	v231213:	IJ seems to be getting picky with column names. This version skips the column name check line ~163. Fixed bad boolean command in manual selection.
	v231213b:	Display of statistics and frequency on ramp for small numbers of features is disabled.
	v231214:	Formatting options added for ROI labels. Removed overly restricted Min and Max Line requirements. Restore ROI names now working.
	v240112:	Frequency plots again. v240119: But not if insufficient stats. F1: Updated getColorFromColorName function (012324). F2: updated function unCleanLabel.
	v240709:	Updated colors.
	v250424:	Fixed interval number dialog that should not have allowed hidden decimals.
	v250509:	Initial fontSize is integer to match addNumber dp.
 */
macro "ROI Color Coder with ROI Labels" {
	macroL = "BAR_ROI_Color_Coder_ROI-Manager-Labels_ASC_v250509.ijm";
	macroV = substring(macroL, lastIndexOf(macroL, "_v") + 2, maxOf(lastIndexOf(macroL, "."), lastIndexOf(macroL, "_v") + 8));
	requires("1.53g"); /* Uses expandable arrays */
	close("*Ramp"); /* cleanup: closes previous ramp windows, NOTE this is case insensitive */
	call("java.lang.System.gc");
	if (!checkForPluginNameContains("Fiji_Plugins")) exit("Sorry this macro requires some functions in the Fiji_Plugins package");
	/* Needs Fiji_plugins for autoCrop */
	saveSettings;
	ascPrefsKey = "asc.ROICoder.Prefs.";
	imageN = nImages;
	if (imageN==0){
		showMessageWithCancel("No images open or the ROI Manager is empty...\n"
		+ "Run demo? (Results Table and ROI Manager will be cleared)");
	    runDemo();
	}
	orID = getImageID(); /* get id of image and title */
	t = getTitle();
	tPath = getDirectory("image");
	if (tPath=="") tPath = File.directory;
	if (indexOf(tPath, "AutoRun")>=0) tPath = "";
	/* Check to see if there is a location already set for ROI selection and/or he summary
	0=rectangle, 1=oval, 2=polygon, 3=freehand, 4=traced, 5=straight line, 6=segmented line, 7=freehand line, 8=angle, 9=composite and 10=point.
	*/
	selType = selectionType;
	if (selType>=0 && selType<4) {
		getSelectionBounds(selPosStartX, selPosStartY, originalSelEWidth, originalSelEHeight);
		/*  smallest rectangle that can completely contain the current selection */
		selectionExists = true;
	}
	else selectionExists = false;
	run("Select None");
	if (roiManager("count")>0) roiManager("deselect");
	/*
	Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* Set the background to white */
	run("Colors...", "foreground=black background=white selection=yellow"); /* Set the preferred colors for these macros */
	setOption("BlackBackground", false);
	selectImage(orID);
	if (is("Inverting LUT")) run("Invert LUT");
	nROIs = checkForRoiManager(); /* macro requires that the objects are in the ROI manager */
	checkForResults(); /* macro requires that there are results to display */	
	/* Check for unwanted black border */
	oImageDepth = bitDepth();
	if (!is("binary") && nROIs<1){
		yMax = Image.height-1;	xMax = Image.width-1;
		cornerPixels = newArray(getPixel(0, 0), getPixel(1, 1), getPixel(0, yMax), getPixel(xMax, 0), getPixel(xMax, yMax), getPixel(xMax-1, yMax-1));
		Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
		if (cornerMax!=cornerMin){
			actionOptions = newArray("Remove black edge objects", "Invert, then remove black edge objects", "Exit", "Feeling lucky");
			Dialog.create("Border pixel inconsistency");
				Dialog.addMessage("cornerMax=" + cornerMax + " but cornerMin=" + cornerMin + " and cornerMean = " + cornerMean + " problem with image border");
				Dialog.addRadioButtonGroup("Actions:", actionOptions, actionOptions.length, 1, "Remove black edge objects");
			Dialog.show();
				edgeAction = Dialog.getRadioButton();
			if (edgeAction=="Exit") restoreExit();
			else if (edgeAction=="Invert, then remove black edge objects"){
				run("Invert");
				removeBlackEdgeObjects();
			}
			else if (edgeAction=="Remove white edge objects, then invert"){
				removeBlackEdgeObjects();
				run("Invert");
			}
		}
		/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
			i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
		if (cornerMean<1 && cornerMean!=-1) {
			inversion = getBoolean("The corner mean has an intensity of " + cornerMean + ", do you want the intensities inverted?", "Yes Please", "No Thanks");
			if (inversion) run("Invert");
		}
	}
	checkForUnits(); /* Required function */
	getPixelSize(unit, pixelWidth, pixelHeight);
	medianBGIs = guessBGMedianIntensity();
	bgI = round((medianBGIs[0] + medianBGIs[1] + medianBGIs[2])/3);
	lcf = (pixelWidth + pixelHeight)/2; /* length conversion factor needed for morph. centroids */
	nRes = nResults;
	tSize = Table.size;
	if (nRes==0 && tSize>0){
		oTableTitle = Table.title;
		renameTable = getBoolean("There is no Results table but " + oTableTitle + " has " + tSize + " rows:", "Rename to Results", "No, I will take may chances");
		if (renameTable) {
			Table.rename(oTableTitle, "Results");
			nRes = nResults;
		}
	}
	if (nRes!=nROIs){
		measureROIs = getBoolean("There is no Results table but " + nROIs + " ROIs", "Measure theROIs?", "Exit");
		if (measureROIs){
			roiManager("Deselect");
			roiManager("Measure");
			nRes = nResults;
		}
		else restoreExit("Goodbye");
	}
	if (nROIs<=1) restoreExit("Exit: ROI Manager has only \(" + nROIs + "\) entries."); /* exit so that this ambiguity can be cleared up */
	items = nROIs;
	run("Remove Overlay");
	countNaN = 0; /* Set this counter here so it is not skipped by later decisions */
	menuLimit = 0.8 * screenHeight; /* used to limit menu size for small screens */
	// menuLimit = 700; /* for testing only resolution options only */
	outlineStrokePC = 6; /* default outline stroke: % of font size */
	sup2 = fromCharCode(178);
	degreeChar = fromCharCode(0x00B0);
	sigmaChar = fromCharCode(0x03C3);
	geq = fromCharCode(0x2265);
	ums = getInfo("micrometer.abbreviation");
	grayChoices = newArray("white", "black", "off-white", "off-black", "light_gray", "gray", "dark_gray");
	colorChoicesStd = newArray("red", "green", "blue", "cyan", "magenta", "yellow", "pink", "orange", "violet");
	colorChoicesMod = newArray("aqua_modern", "blue_accent_modern", "blue_dark_modern", "blue_modern", "blue_honolulu", "gray_modern", "green_dark_modern", "green_modern", "green_modern_accent", "green_spring_accent", "orange_modern", "pink_modern", "purple_modern", "red_n_modern", "red_modern", "tan_modern", "violet_modern", "yellow_modern");
	colorChoicesNeon = newArray("jazzberry_jam", "radical_red", "wild_watermelon", "outrageous_orange", "supernova_orange", "atomic_tangerine", "neon_carrot", "sunglow", "laser_lemon", "electric_lime", "screamin'_green", "magic_mint", "blizzard_blue", "dodger_blue", "shocking_pink", "razzle_dazzle_rose", "hot_magenta");
	colorChoicesFSU = newArray("garnet", "gold", "stadium_night", "westcott_water", "vault_garnet", "legacy_blue", "plaza_brick", "vault_gold");
	allColors = Array.concat(colorChoicesStd, colorChoicesMod, colorChoicesNeon, colorChoicesFSU, grayChoices);
	tN = stripKnownExtensionFromString(unCleanLabel(t)); /* File.nameWithoutExtension is specific to last opened file, also remove special characters that might cause issues saving file */
	if (lengthOf(tN)>43) tNL = substring(tN, 0, 21) + "..." + substring(tN, lengthOf(tN)-21);
	else tNL = tN;
	imageHeight = getHeight(); imageWidth = getWidth();
	rampH = round(0.89 * imageHeight); /* suggest ramp slightly small to allow room for labels */
	acceptMinFontSize = true;
	fontSize = maxOf(10, round(imageHeight/28)); /* default fonts size based on imageHeight */
	imageDepth = bitDepth(); /* required for shadows at different bit depths */
	headings = split(String.getResultsHeadings, "\t"); /* the tab specificity avoids problems with unusual column titles */
	headingsWithRange = newArray;
	warningTxt = "";
	for (i=0, countH=0; i<lengthOf(headings); i++) {
		resultsColumn = newArray(items);
		headingClean = cleanLabel(headings[i]);
		if (headingClean!=headings[i]){
			if (Table.columnExists(headings[i])){
				Table.renameColumn(headings[i], headingClean);
				headings[i] = headingClean;
			}
			else 
				warningTxt += "IJ claims that it cannot find a column named '" + headings[i] + "'\n";
		}
		if (warningTxt!="")
			IJ.log(warningTxt + "This sometimes happens with files exported from Excel\nHint: Resave from IJ then reimport the resaved version");
		for (j=0; j<items; j++)
			resultsColumn[j] = getResult(headings[i], j);
		Array.getStatistics(resultsColumn, min, max, null, null);
		if (min!=max && min>=0 && !endsWith(max, "Infinity")) { /* No point in listing parameters without a range , also, the macro does not handle negative numbers well (let me know if you need them)*/
			headingsWithRange[countH] = headings[i] + ":  " + min + " - " + max;
			countH++;
		}
	}
	if (headingsWithRange[0]==" :  Infinity - -Infinity")
		headingsWithRange[0] = "Object" + ":  1 - " + items; /* relabels ImageJ ID column */
	headingsWithRange = Array.trim(headingsWithRange, countH);
	if (imageN>1){  /* workaround for issue with duplicate names for single open image */
		imageList = removeDuplicatesInArray(getList("image.titles"), false);
		imageN = lengthOf(imageList);
	}
	subset = false;
	subsetROIs = "---ROI#s \(starting at 1\) separated by commas---";
	if (selectionExists){
		batchMode = is("Batch Mode"); /* Store batch status mode before toggling */
		if (!batchMode) setBatchMode(true); /* Toggle batch mode on if 
		setBatchMode(true);
		/* finds sub-elements inside and at selection */
		roiManager("select", 0);
		roiStart = Roi.getName;
		roiManager("Deselect");
		run("Restore Selection");
		roiManager("Add");
		roiManager("select", 0);
		roiStart2 = Roi.getName;
		if (roiStart==roiStart2) roiManager("select", items);
		else roiManager("select", 0);
		iTempROI = roiManager("index");
		roiManager("Rename", "Temp_SelectionROI");
		for (i=0, nSels=0; i<items + 1; i++){
			if (i!=iTempROI){
				// roiManager("deselect");
				roiManager("select", i);
				roiSize = getValue("selection.size");
				roiManager("Select", newArray(i, iTempROI));
				roiManager("AND");
				if (getValue("selection.size")==roiSize){
					subsetROIs += "" + i + 1 + ", ";
					nSels++;
				}
			}
		}
		roiManager("deselect");
		RoiManager.selectByName("Temp_SelectionROI");
		if (roiManager("index")==iTempROI)	roiManager("delete");
		roiManager("deselect");
		if (endsWith(subsetROIs, ", ")) subsetROIs = substring(subsetROIs, 0, lengthOf(subsetROIs)-1);
		if (!batchMode) setBatchMode(false); /* Toggle batch mode off */ 
	}
	infoColor = "#006db0"; /* Honolulu blue */
	instructionColor = "#798541"; /* green_dark_modern (121, 133, 65) AKA Wasabi */
	infoWarningColor = "#ff69b4"; /* pink_modern AKA hot pink */
	infoFontSize = 12;
	/* Create initial dialog prompt to determine parameters */
	Dialog.create("Parameter Selection: " + macroL);
		/* if called from the BAR menu there will be no macro.filepath so the following checks for that */
		startInfo = "Filename: " + tNL + "\nImage has " + nROIs + " ROIs that will be color coded";
		if (tPath.length>60) startInfo += "\nDirectory: " + substring(tPath, 0, tPath.length / 2) + "...\n       ..." + substring(tPath, tPath.length / 2);
		Dialog.setInsets(0, 10, 20);
		Dialog.addMessage(startInfo, infoFontSize + 1.5, infoColor);
		Dialog.setInsets(0, 20, 0);
		Dialog.addDirectory("Output directory:", tPath);
		Dialog.setInsets(0, 20, 10);
		if (imageN==1){
			colImage = t;
			colImageL = lengthOf(colImage);
			if (colImageL>50) colImage = "" + substring(colImage, 0, 24) + "..." + substring(colImage, colImageL-24);
			Dialog.setInsets(0, 40, 0);
			Dialog.addMessage("Image for coloring is: " + colImage, infoFontSize, infoColor);
		}
		else if (imageN>5) Dialog.addChoice("Image for color coding", imageList, t);
		else Dialog.addRadioButtonGroup("Choose image for color coding:    ", imageList, imageN, 1, imageList[0]);
		iDefHeading = indexOfArrayThatStartsWith(headingsWithRange, call("ij.Prefs.get", ascPrefsKey + "parameter", "Area"), 1);
		Dialog.addChoice("Parameter", headingsWithRange, headingsWithRange[iDefHeading]);
		luts=getLutsList(); /* I prefer this to new direct use of getList used in the recent versions of the BAR macro YMMV */
		Dialog.addChoice("LUT:", luts, call("ij.Prefs.get", ascPrefsKey + "lut", luts[0]));
		Dialog.setInsets(0, 170, 0);
		Dialog.addCheckbox("Reverse LUT?", call("ij.Prefs.get", ascPrefsKey + "revLut", false));
		Dialog.addMessage("Color Coding:______Borders, Filled ROIs or None \(just labels\)?", infoFontSize, instructionColor);
		Dialog.setInsets(5, 20, 0);
		Dialog.addNumber("Outlines or Solid?", 0, 0, parseInt(call("ij.Prefs.get", ascPrefsKey + "stroke", 0)), "Width \(pixels\), 0=fill ROIs, -1= label only");
		Dialog.setInsets(0, 20, 0);
		Dialog.addSlider("Coding opacity (%):", 0, 100, parseInt(call("ij.Prefs.get", ascPrefsKey + "opacity", 100)));
		Dialog.addCheckbox("Restore original ROI names after labeling", call("ij.Prefs.get", ascPrefsKey + "roiNameRestore", true));
		Dialog.setInsets(10, 20, 0);
		Dialog.addCheckbox("Apply colors and formatted labels to image copy \(no change to original\)", true);
		if (selectionExists) {
			Dialog.setInsets(10, 20, 0);
			Dialog.addMessage("An area selection exists that can be used for ROI selection location,\nyou can edit it here:", infoFontSize, infoColor);
			Dialog.addNumber("Starting", selPosStartX, 0, 5, "X");
			Dialog.setInsets(-28, 150, 0);
			Dialog.addNumber("Starting", selPosStartY, 0, 5, "Y");
			Dialog.addNumber("Selected", originalSelEWidth, 0, 5, "Width");
			Dialog.setInsets(-28, 150, 0);
			Dialog.addNumber("Selected", originalSelEHeight, 0, 5, "Height");
		}
		restrictions = newArray("No");
		restriction = call("ij.Prefs.get", ascPrefsKey + "restriction", "No");
		if (selectionExists) restrictions = Array.concat(restrictions, "ROIs within selection");
		else if (restriction=="ROIs within selection") restriction = "No";
		restrictions = Array.concat(restrictions, "ROIs listed below", "ROIs from csv file");
		Dialog.addRadioButtonGroup("Restrict ROI list?", restrictions, 1, restrictions.length, restriction);
		Dialog.setInsets(0, 20, 0);
		subsetROIs = call("ij.Prefs.get", ascPrefsKey + "subsetROIs", subsetROIs);
		Dialog.addString("ROI subset", subsetROIs, 40);
		importCSVPath = call("ij.Prefs.get", ascPrefsKey + "importCSVPath", "---csv file expected---");
		Dialog.addFile("Import ROI subset", importCSVPath);
		Dialog.addCheckbox("Diagnostics", false);
	Dialog.show;
		tPath = Dialog.getString();
		if (imageN==1) imageChoice = t;
		else if (imageN > 5) imageChoice = Dialog.getChoice();
		else imageChoice = Dialog.getRadioButton();
		parameterWithLabel = Dialog.getChoice;
		parameter = substring(parameterWithLabel, 0, indexOf(parameterWithLabel, ":  "));
		call("ij.Prefs.set", ascPrefsKey + "parameter", parameter);
		lut = Dialog.getChoice;
		call("ij.Prefs.set", ascPrefsKey + "lut", lut);
		revLut = Dialog.getCheckbox;
		call("ij.Prefs.set", ascPrefsKey + "revLut", revLut);
		stroke = Dialog.getNumber;
		call("ij.Prefs.set", ascPrefsKey + "stroke", stroke);
		opacity = Dialog.getNumber();
		call("ij.Prefs.set", ascPrefsKey + "opacity", opacity);
		roiNameRestore = Dialog.getCheckbox();
		call("ij.Prefs.set", ascPrefsKey + "roiNameRestore", roiNameRestore);
		alpha = String.pad(toHex(255 * opacity / 100), 2);
		addLabels = Dialog.getCheckbox;
		if (selectionExists) {
			selPosStartX = Dialog.getNumber;
			selPosStartY = Dialog.getNumber;
			originalSelEWidth = Dialog.getNumber;
			originalSelEHeight = Dialog.getNumber;
		}
		restriction = Dialog.getRadioButton();
		call("ij.Prefs.set", ascPrefsKey + "restriction", restriction);
		subsetROIs = Dialog.getString();
		call("ij.Prefs.set", ascPrefsKey + "subsetROIs", subsetROIs);
		importCSVPath = Dialog.getString();
		call("ij.Prefs.set", ascPrefsKey + "importCSVPat", importCSVPath);
		diagnostics = Dialog.getCheckbox();
	if (restriction=="ROIs from csv file" && !startsWith(importCSVPath, "---")){
		subsetROIs = File.openAsString(importCSVPath);
		subset = true;
	}
	else if (restriction=="ROIs listed below"){
		if (!startsWith(subsetROIs, "---"))
			subset = true;
	}
	else if (restriction=="ROIs within selection") {
		subset = false;
		subsetROIs = "";
		setBatchMode(true);
		/* finds sub-elements inside and at selection */
		roiManager("select", 0);
		roiStart = Roi.getName;
		roiManager("Deselect");
		run("Restore Selection");
		roiManager("Add");
		roiManager("select", 0);
		roiStart2 = Roi.getName;
		if (roiStart==roiStart2) roiManager("select", nROIs);
		else roiManager("select", 0);
		iTempROI = roiManager("index");
		roiManager("Rename", "Temp_SelectionROI");
		for (i=0, nSels=0; i<nROIs + 1; i++){
			if (i!=iTempROI){
				// roiManager("deselect");
				roiManager("select", i);
				roiSize = getValue("selection.size");
				roiManager("Select", newArray(i, iTempROI));
				roiManager("AND");
				if (getValue("selection.size")==roiSize){
					subsetROIs += "" + i + 1 + ", ";
					nSels++;
				}
			}
		}
		roiManager("deselect");
		RoiManager.selectByName("Temp_SelectionROI");
		if (roiManager("index")==iTempROI)
			roiManager("delete");
		roiManager("deselect");
		if (endsWith(subsetROIs, ", "))
			subsetROIs = substring(subsetROIs, 0, lengthOf(subsetROIs)-1);
		subset = true;	
		setBatchMode(false);
	}
	if (subset==true){
		subsetArray = split(subsetROIs, ", , ");
		subsetArray = Array.sort(subsetArray);
		if (lengthOf(subsetArray)>0){
			items = lengthOf(subsetArray);
			IJ.log("Analysis restricted to " + items + " selected ROIs:");
			Array.print(subsetArray);
			iROIs = newArray;
			for (i=0; i<items; i++) iROIs[i] = parseInt(subsetArray[i])-1;
		}
		else subset = false;
	}	
	if (subset==false) iROIs = Array.getSequence(nROIs);
	if (!diagnostics) setBatchMode(true);
	call("ij.Prefs.set", ascPrefsKey + "subset", subset);
	selectWindow(imageChoice);
	orID = getImageID(); /* update after selection of image */
	t = getTitle();
	unitLabel = cleanLabel(unitLabelFromString(parameter, unit));
	unitLabel = replace(unitLabel, degreeChar, "degrees"); /* replace lonely ° symbol */
	/* get values for chosen parameter */
	values = newArray();
	if (parameter=="Object") for (i=0; i<iROIs.length; i++) values[i] = iROIs[i] + 1;
	else for (i=0; i<iROIs.length; i++) values[i]= getResult(parameter, iROIs[i]);
	Array.getStatistics(values, arrayMin, arrayMax, arrayMean, arraySD);
	arrayRange = arrayMax-arrayMin;
	rampMin = arrayMin;
	rampMax = arrayMax;
	rampMax = rangeFinder(rampMax, true);
	rampMin = rangeFinder(rampMin, false);
	rampRange = rampMax - rampMin;
	if (rampMin<0.05 * rampRange){
		rampMin = 0;
		rampRange = rampMax;
	}
	intStr = d2s(rampRange, -1);
	intStr = substring(intStr, 0, indexOf(intStr, "E"));
	numIntervals =  parseFloat(intStr);
	if (numIntervals>4)
		if (endsWith(d2s(numIntervals, 3), ".500")) numIntervals = round(numIntervals * 2);
	else if (numIntervals>=2){
		if (endsWith(d2s(numIntervals, 3), "00")){
			if (endsWith(d2s(numIntervals * 5, 3), "000")) numIntervals = round(numIntervals * 5);
			else numIntervals = round(numIntervals * 10);
		}
	}
	else if (numIntervals<2) numIntervals = Math.ceil(10 * numIntervals);
	else numIntervals = Math.ceil(5 * numIntervals);
	 /* Just in case parameter still has units appended... */
	pu1 = indexOf(parameter, "\("); pu2 = indexOf(parameter, "\)"); pu3 = indexOf(parameter, "0-90");  /* Exception for 0-90° label */
	if (pu1>0 && pu2>0 && pu3<0) parameterLabel = parameter.substring(0, pu1);
	else parameterLabel = parameter;
	parameterLabelExp = expandLabel(parameterLabel);
	/* Create dialog prompt to determine look */
	Dialog.create("Ramp \(Legend\) Options \(LUT " + lut + "\): ROI Color Coder V:" + macroV);
		Dialog.addString("Parameter label - edit for ramp/legend/title", parameterLabelExp, 30);
		Dialog.setInsets(-5, 20, 5);
		Dialog.addMessage("Do NOT include the 'unit' in the this label as it will be added from options below...\)", infoFontSize, infoWarningColor);
		unitChoices = newArray("Manual", "None");
		unitLinearChoices = newArray(unitLabel, unit, "pixels", "%", "arb.");
		if (unit=="microns" && (unitLabel!=ums || unitLabel!=ums + sup2)) unitLinearChoices = Array.concat(ums, unitLinearChoices);
		unitAngleChoices = newArray(degreeChar, "degrees", "radians");
		unitAreaChoices = newArray(unit + sup2, "pixels" + sup2);
		if (indexOf(parameter, "Area")>=0){
			if (unit=="microns" && (unitLabel!=ums || unitLabel!=ums + sup2)) unitAreaChoices = Array.concat(ums + sup2, unitAreaChoices);
			unitChoices = Array.concat(unitAreaChoices, unitChoices, unitLinearChoices, unitAngleChoices);	
		}
		else if (indexOf(parameter, "Angle")>=0) unitChoices = Array.concat(unitAngleChoices, unitChoices, unitLinearChoices, unitAreaChoices);
		else unitChoices = Array.concat(unitLinearChoices, unitChoices, unitAreaChoices, unitAngleChoices);
		if (unitLabel=="None" || unitLabel=="") dialogUnit = "";
		else dialogUnit = " " + unitLabel;
		Dialog.addChoice("Unit label \(" + unitLabel + "\):", unitChoices, unitChoices[0]);
		Dialog.setInsets(-38, 400, 0);
		Dialog.addMessage("Default shown is based on\nthe selected parameter", infoFontSize, infoColor);
		unitSeparators = newArray("\(unit\)", ", unit", "[unit]", "{unit}");
		iUnitSeparators = indexOfArray(unitSeparators, call("ij.Prefs.get", ascPrefsKey + "unitSeparator", "\(unit\)"), unitSeparators[0]);
		Dialog.addChoice("Unit separator\(s\) in label:", unitSeparators, unitSeparators[iUnitSeparators]);
		Dialog.setInsets(0, 20, 0);
		rangeMessage = "Original data range:       " + arrayMin + "-" + arrayMax + " \(range = " + (arrayRange) + " " + dialogUnit + "\)";
		Dialog.addMessage(rangeMessage, infoFontSize, infoColor);
		Dialog.addString("Legend \(ramp\) data range \(" + rampRange + "\):", rampMin + "-" + rampMax, 15);
		Dialog.setInsets(-20, 400, 0); /* top, left, bottom */
		Dialog.addMessage("\(e.g. n-n\)", infoFontSize + 2, instructionColor);
		Dialog.addString("LUT colors applied across range \(n-n format\):", arrayMin + "-" + arrayMax, 15);
		Dialog.setInsets(-7, 10, 7);
		Dialog.addMessage("The LUT gradient will be remapped to this range \(limited by the ramp min and max\)\nBeyond this range the top and bottom LUT colors will be applied", infoFontSize, instructionColor);
		Dialog.setInsets(-4, 120, 0);
		Dialog.addCheckbox("Add legend \(ramp\) labels at Min. & Max. if inside Range", true);
		Dialog.addNumber("No. of major intervals:", round(numIntervals), 0, 3, "Major tick count will be + 1 more than this");
		defTickN = parseInt(substring(d2s(rampRange/numIntervals, 1), 0, 1)) - 1;
		if (defTickN<2) defTickN = 4;
		Dialog.addNumber("No. of ticks between major ticks:", defTickN, 0, 3, "i.e. 4 ticks for 5 minor intervals");
		Dialog.addChoice("Decimal places:", newArray("Auto", "Manual", "Scientific", "0", "1", "2", "3", "4"), "Auto");
		Dialog.addChoice("Legend \(ramp\) height \(pixels\):", newArray(d2s(rampH, 0), 128, 256, 512, 1024, 2048, 4096), rampH);
		Dialog.setInsets(-38, 350, 0);
		Dialog.addMessage(rampH + " pixels suggested\nby image height", infoFontSize, infoColor);
		fontStyleChoice = newArray("bold", "italic", "bold italic", "unstyled");
		iFontStyle = indexOfArray(fontStyleChoice, call("ij.Prefs.get", ascPrefsKey + "rampFStyle", "bold"), 0);
		Dialog.addChoice("Font style:", fontStyleChoice, fontStyleChoice[iFontStyle]);
		fontNameChoice = getFontChoiceList();
		Dialog.addChoice("Font name:", fontNameChoice, fontNameChoice[0]);
		Dialog.addNumber("Font_size \(height\):", fontSize, 0, 3, "pixels");
		colorChoicesStd = newArray("white", "black", "light_gray", "gray", "dark_gray", "red", "green", "blue", "cyan", "magenta", "yellow", "pink", "orange");
		labelColor = call("ij.Prefs.get", ascPrefsKey + "labelColor", "white");
		Dialog.addChoice("ROI label color:", colorChoicesStd, labelColor);
		Dialog.addNumber("ROI label font size:", round(fontSize/2), 0, 3, "pixels");
		labelFormatChoices = newArray("Bold ROI label", "Draw background behind ROI label");
		labelFormatChecks = newArray(call("ij.Prefs.get", ascPrefsKey + "labelBold", true), call("ij.Prefs.get", ascPrefsKey + "labelBkgrd", true));
		Dialog.setInsets(0, 70, 0);
		Dialog.addCheckboxGroup(1, 2, labelFormatChoices, labelFormatChecks);
		rampFormatChoices = newArray("Draw border and top/bottom ticks", "Force vertical \(rotated\) legend label", "Off-white interior legend labels");
		brdr = call("ij.Prefs.get", ascPrefsKey + "brdr", true);
		rotLegend = call("ij.Prefs.get", ascPrefsKey + "rotLegend", false);
		offWhiteIntRampLabels = call("ij.Prefs.get", ascPrefsKey + "offWhiteIntRampLabels", false);
		rampFormatChecks = newArray(brdr, rotLegend, offWhiteIntRampLabels);
		if (iROIs.length>5){
			rampFormatChoices = Array.concat(rampFormatChoices, "Frequency plotted inside legend"); /* Assumed that a histogram is not useful enough if you only have 5 objects of less */
			freqDistRamp = call("ij.Prefs.get", ascPrefsKey + "freqDistRamp", true);
			rampFormatChecks = Array.concat(rampFormatChecks, freqDistRamp);
		}
		Dialog.setInsets(0, 70, 0);
		Dialog.addCheckboxGroup(2, 2, rampFormatChoices, rampFormatChecks);
		if (iROIs.length>3){ /* Assumed that stats are not useful enough if you only have 3 objects or less  */
			Dialog.setInsets(3, 0, -2);
			rampStatsOptions = newArray("No", "Linear", "Ln");
			statsRampLines = call("ij.Prefs.get", ascPrefsKey + "statsRampLines", "Linear");
			Dialog.setInsets(-20, 15, 18);
			Dialog.addRadioButtonGroup("Legend \(Ramp\) Stats: Mean and " + fromCharCode(0x00B1) + sigmaChar + " on ramp \(if \"Ln\" then outlier " + sigmaChar + " will be \"Ln\" too\)", rampStatsOptions, 1, 5, statsRampLines);
			/* will be used for sigma outlines too */
			statsRampTick = parseInt(call("ij.Prefs.get", ascPrefsKey + "statsRampTickL", 50));
			Dialog.addNumber("Tick length:", statsRampTick, 0, 3, "% of major tick. Also Min. & Max. Lines");
		}
		thinLinesFontSTweak = parseInt(call("ij.Prefs.get", ascPrefsKey + "thinLinesFontSTweak", 100));
		Dialog.addNumber("Label font:", 100, 0, 3, "% of font size. Also Min. & Max. Lines");
		Dialog.setInsets(4, 120, 0);
		Dialog.addHelp("https://imagej.net/doku.php?id=macro:roi_color_coder");
	Dialog.show;
		parameterLabel = Dialog.getString;
		unitLabel = Dialog.getChoice();
		if (unitLabel=="None") unitLabel = "";
		unitSeparator = Dialog.getChoice();
		call("ij.Prefs.set", ascPrefsKey + "unitSeparator", unitSeparator);
		rangeS = Dialog.getString; /* changed from original to allow negative values - see below */
		rangeLUT = Dialog.getString;
		if (rangeLUT=="same as ramp range") rangeLUT = rangeS; /* maintained for old preferences */
		rampMinMaxLines = Dialog.getCheckbox;
		numIntervals = Dialog.getNumber; /* The number intervals along ramp */
		numLabels = numIntervals + 1;  /* The number of major ticks/labels is one more than the intervals */
		minorTicks = Dialog.getNumber; /* The number of minor ticks/labels is one less than the intervals */
		dpChoice = Dialog.getChoice;
		rampHChoice = parseInt(Dialog.getChoice);
		fontStyle = Dialog.getChoice;
		call("ij.Prefs.set", ascPrefsKey + "rampFStyle", fontStyle);
		if (fontStyle=="unstyled") fontStyle="";
		fontStyle += " antialiased"; /* why not? */
		fontName = Dialog.getChoice();
		fontSize = Dialog.getNumber();
		labelColor = Dialog.getChoice();
		call("ij.Prefs.set", ascPrefsKey + "labelColor", labelColor);
		labelFontSize = Dialog.getNumber();
		labelBold = Dialog.getCheckbox();
		call("ij.Prefs.set", ascPrefsKey + "labelBold", labelBold);
		labelBkgrd = Dialog.getCheckbox();
		call("ij.Prefs.set", ascPrefsKey + "labelBkgrd", labelBkgrd);
		brdr = Dialog.getCheckbox();
		call("ij.Prefs.set", ascPrefsKey + "brdr", brdr);
		rotLegend = Dialog.getCheckbox();
		call("ij.Prefs.set", ascPrefsKey + "rotLegend", rotLegend);
		offWhiteIntRampLabels = Dialog.getCheckbox();
		call("ij.Prefs.set", ascPrefsKey + "offWhiteIntRampLabels", offWhiteIntRampLabels);
		if (iROIs.length>5){
			freqDistRamp = Dialog.getCheckbox();
			call("ij.Prefs.set", ascPrefsKey + "freqDistRamp", freqDistRamp);
		}
		else {
			freqDistRamp = false;
		}
		if (iROIs.length>3){
			statsRampLines = Dialog.getRadioButton;
			call("ij.Prefs.set", ascPrefsKey + "statsRampLines", statsRampLines);
			statsRampTickL = Dialog.getNumber;
			call("ij.Prefs.set", ascPrefsKey + "statsRampTickL", statsRampTickL);
		}
		else statsRampLines = "No";
		thinLinesFontSTweak = Dialog.getNumber;
		call("ij.Prefs.set", ascPrefsKey + "thinLinesFontSTweak", thinLinesFontSTweak);
	if (imageChoice!=t) {
		t = imageChoice;
		tN = stripKnownExtensionFromString(t);
		tN = unCleanLabel(tN);
	}
	if (fontSize<10) {
		acceptMinFontSize = getBoolean("A font size of 10 is the minimum recommended font size for the macro; increase font size to 10?");
		if (acceptMinFontSize) fontSize = 10;
	}
	rampParameterLabel= cleanLabel(parameterLabel);
	rampW = round(rampH/8); /* this will be updated later */
	if (statsRampLines=="Ln") rampParameterLabel= rampParameterLabel + " \(ln stats\)";
	rampUnitLabel = unitLabel.replace("^-", "-");
	if (((rotLegend && rampHChoice==rampH)) || (rampW < maxOf(getStringWidth(rampUnitLabel), getStringWidth(rampParameterLabel)))) rampH = imageHeight - fontSize; /* tweaks automatic height selection for vertical legend */
	else rampH = rampHChoice;
	rampW = round(rampH/8);
	range = split(rangeS, "-");
	if (lengthOf(range)==1) {
		rampMin = NaN; rampMax= parseFloat(range[0]);
	} else {
		rampMin = parseFloat(range[0]); rampMax= parseFloat(range[1]);
	}
	if (indexOf(rangeS, "-")==0) rampMin = 0 - rampMin; /* checks to see if rampMin is a negative value (lets hope the rampMax isn't). */
	lutRange = split(rangeLUT, "-");
	if (lengthOf(lutRange)==1) {
		minLUT = NaN; maxLUT = parseFloat(lutRange[0]);
	} else {
		minLUT = parseFloat(lutRange[0]); maxLUT = parseFloat(lutRange[1]);
	}
	if (indexOf(rangeLUT, "-")==0) minLUT = 0 - minLUT; /* checks to see if min is a negative value (lets hope the max isn't). */
	/* Restrict LUT range to be within set ramp range: */
	minLUT = maxOf(minLUT, rampMin);
	maxLUT = minOf(maxLUT, rampMax);
	fontSR2 = fontSize * thinLinesFontSTweak/100;
	rampLW = maxOf(1, round(rampH/512)); /* ramp line width with a minimum of 1 pixel */
	minmaxLW = round(rampLW / 4); /* line widths for ramp stats */
	if (isNaN(rampMin)) rampMin = arrayMin;
	if (isNaN(rampMax)) rampMax = arrayMax;
	rampRange = rampMax - rampMin;
	coeffVar = arraySD*100/arrayMean;
	if (iROIs.length>2) {
		sortedValues = Array.copy(values); sortedValues = Array.sort(sortedValues); /* all this effort to get the median without sorting the original array! */
		arrayQuartile = newArray(3);
		for (q=0; q<3; q++) arrayQuartile[q] = sortedValues[round((q + 1) * iROIs.length / 4)];
		IQR = arrayQuartile[2] - arrayQuartile[0];
	}
	else IQR = NaN;
	mode = NaN;
	autoDistW = NaN;
	/* The following section produces frequency/distribution data for the optional distribution plot on the ramp */
	if (IQR>0) {	/* For some data sets IQR can be zero which produces an error in the distribution calculations */
		autoDistW = 2 * IQR * exp((-1/3)*log(iROIs.length));	/* Uses the optimal binning of Freedman and Diaconis (summarized in [Izenman, 1991]), see https://www.fmrib.ox.ac.uk/datasets/techrep/tr00mj2/tr00mj2/node24.html */
		autoDistWCount = round(arrayRange/autoDistW);
		arrayDistFreq =  newArray(autoDistWCount);
		arrayDistInt = newArray(autoDistWCount);
		for (f=0; f<autoDistWCount + 1; f++)
			arrayDistInt[f] = arrayMin + f * autoDistW;
		modalBin = 0;
		freqMax = 0;
		for (f=0; f<autoDistWCount; f++) {
			for (i=0; i<iROIs.length; i++){
				if ((values[i]>=arrayDistInt[f]) && (values[i]<arrayDistInt[f+1])) arrayDistFreq[f] += 1;
			}
			if (arrayDistFreq[f]>freqMax) {
				freqMax = arrayDistFreq[f];
				modalBin = f;
			}
		}
		/* use adjacent bin estimate for mode */
		if (modalBin > 0)
			mode = (arrayMin + (modalBin * autoDistW)) + autoDistW * ((arrayDistFreq[modalBin]-arrayDistFreq[maxOf(0, modalBin-1)])/((arrayDistFreq[modalBin]-arrayDistFreq[maxOf(0, modalBin-1)]) + (arrayDistFreq[modalBin]-arrayDistFreq[minOf(arrayDistFreq.length-1, modalBin + 1)])));
		Array.getStatistics(arrayDistFreq, freqMin, freqMax, freqMean, freqSD);
		if (isNaN(freqSD) || isNaN(mode)){
			freqDistRamp = false;
			IJ.log("Unable to generate statistics required for in-legend histogram: freqSD = " + freqSD + ", mode = " + mode);
		}
		/* End of frequency/distribution section */
	}
	else freqDistRamp = false;
	sIntervalsR = round(rampRange/arraySD);
	meanPlusSDs = newArray(sIntervalsR);
	meanMinusSDs = newArray(sIntervalsR);
	for (s=0; s<sIntervalsR; s++) {
		meanPlusSDs[s] = arrayMean + (s*arraySD);
		meanMinusSDs[s] = arrayMean-(s*arraySD);
	}
	/* Calculate ln stats for ramp if requested */
	lnValues = lnArray(values);
	Array.getStatistics(lnValues, null, null, lnMean, lnSD);
	expLnMeanPlusSDs = newArray(sIntervalsR);
	expLnMeanMinusSDs = newArray(sIntervalsR);
	expLnSD = exp(lnSD);
	for (s=0; s<sIntervalsR; s++) {
		expLnMeanPlusSDs[s] = exp(lnMean + s*lnSD);
		expLnMeanMinusSDs[s] = exp(lnMean-s*lnSD);
	}
	/* Create the parameter label */
	if (unitLabel=="Manual") {
		unitLabel = unitLabelFromString(parameter, unit);
			Dialog.create("Manual unit input");
			Dialog.addString("Label:", unitLabel, 8);
			Dialog.addMessage("^2 & um etc. replaced by " + sup2 + " & " + fromCharCode(181) + "m...", infoFontSize, instructionColor);
			Dialog.show();
			unitLabel = Dialog.getString();
	}
	unitLabel= cleanLabel(unitLabel);
	/* Begin object color coding if stroke set */
	if (stroke>=0) {
		/*	Create LUT-map legend	*/
		rampTBMargin = 2 * fontSize;
		canvasH = round(2 * rampTBMargin + rampH);
		canvasH = round(4 * fontSize + rampH);
		canvasW = round(rampH/2);
		tickL = round(rampW/4);
		if (statsRampLines!="No" || rampMinMaxLines) tickL = round(tickL/2); /* reduce tick length to provide more space for inside label */
		if (statsRampLines!="No") tickLR = round(tickL * statsRampTickL/100);
		else tickLR = round(tickL * tickL/50);
		getLocationAndSize(imgx, imgy, imgwidth, imgheight);
		call("ij.gui.ImageWindow.setNextLocation", imgx + imgwidth, imgy);
		tR = replace(tN + "_" + parameterLabel + "_Ramp", " ", "_");
		newImage(tR, "ramp", rampH, rampW, "8-bit"); /* Height and width swapped for later rotation */
		/* ramp color/gray range is horizontal only so must be rotated later */
		if (revLut) run("Flip Horizontally");
		tR = getTitle; /* short variable label for ramp */
		run(lut);
		/* modify lut if requested */
		if (rangeLUT!=rangeS) { /* recode legend if LUT over restricted range */
			rampIncr = 255/rampRange;
			maxLUTi = round((maxLUT-rampMin)*rampIncr);
			minLUTi = round((minLUT-rampMin)*rampIncr);
			lutIncr = 255/(maxLUTi-minLUTi);
			getLut(reds, greens, blues);
			newReds = newArray();newGreens = newArray();newBlues = newArray();
			for (i=0; i<256; i++){
				if (i<minLUTi){
					newReds[i] = reds[0];
					newGreens[i] = greens[0];
					newBlues[i] = blues[0];
				}
				else if (i>maxLUTi){
					newReds[i] = reds[255];
					newGreens[i] = greens[255];
					newBlues[i] = blues[255];
				}
				else {
					newReds[i] = reds[round((i-minLUTi)*lutIncr)];
					newGreens[i] = greens[round((i-minLUTi)*lutIncr)];
					newBlues[i] = blues[round((i-minLUTi)*lutIncr)];
				}
			}
			setLut(newReds, newGreens, newBlues);
		}
		roiColors = hexLutColors(); /* creates a hexColor array: requires function */
		/* continue the legend design */
		/* Frequency line if requested */
		if (freqDistRamp) {
			rampRXF = rampH/(rampRange); /* RXF short for Range X Factor Units/pixel */
			rampRYF = (rampW-2*rampLW)/freqMax; /* RYF short for Range Y Factor Freg/pixel - scale from zero */
			distFreqPosX = newArray();
			distFreqPosY = newArray();
			for (f=0; f<(autoDistWCount); f++) {
				distFreqPosX[f] = (arrayDistInt[f]-rampMin)*rampRXF;
				distFreqPosY[f] = arrayDistFreq[f]*rampRYF;
			}
			distFreqPosXIncr = distFreqPosX[autoDistWCount-1] - distFreqPosX[autoDistWCount-2];
			fLastX = newArray(distFreqPosX[autoDistWCount - 1] + distFreqPosXIncr, "");
			distFreqPosX = Array.concat(distFreqPosX, fLastX);
			freqDLW = maxOf(1, round(rampLW/2));
			setLineWidth(freqDLW);
			for (f=0; f<(autoDistWCount); f++) { /* Draw All Shadows First */
				setColor(0, 0, 0); /* Don't change to "black". Note that this color will be converted to LUT equivalent */
				if (arrayDistFreq[f] > 0) {
					drawLine(distFreqPosX[f]-freqDLW, freqDLW, distFreqPosX[f]-freqDLW, distFreqPosY[f]-freqDLW);
					drawLine(distFreqPosX[f]-freqDLW, distFreqPosY[f]-freqDLW, distFreqPosX[f + 1]-freqDLW, distFreqPosY[f]-freqDLW); /* Draw bar top */
					drawLine(distFreqPosX[f + 1]-freqDLW, freqDLW, distFreqPosX[f + 1]-freqDLW, distFreqPosY[f]-freqDLW); /* Draw bar side */
				}
			}
			for (f=0; f<autoDistWCount; f++) {
				setColor(250, 250, 250); /* Note that this color will be converted to LUT equivalent */
				if (arrayDistFreq[f] > 0) {
					drawLine(distFreqPosX[f], freqDLW, distFreqPosX[f], distFreqPosY[f]);  /* Draw bar side - right/bottom */
					drawLine(distFreqPosX[f], distFreqPosY[f], distFreqPosX[f + 1], distFreqPosY[f]); /* Draw bar cap */
					drawLine(distFreqPosX[f + 1], freqDLW, distFreqPosX[f + 1], distFreqPosY[f]); /* Draw bar side - left/top */
				}
			}
		}
		setColor(0, 0, 0); /* Don't change to "black" */
		setBackgroundColor(255, 255, 255);  /* Don't change to "white" */
		numLabelFontSize = minOf(fontSize, rampH/numLabels);
		if ((numLabelFontSize<10) && acceptMinFontSize) numLabelFontSize = maxOf(10, numLabelFontSize);
		setFont(fontName, numLabelFontSize, fontStyle);
		if (imageDepth!=8 || lut!="Grays") run("RGB Color"); /* converts ramp to RGB if not using grays only */
		setLineWidth(rampLW*2);
		if (brdr) {
			drawRect(0, 0, rampH, rampW);
			/* The next steps add the top and bottom ticks */
			rampWT = rampW + 2*rampLW;
			run("Canvas Size...", "width=" + rampH + " height=" + rampWT + " position=Top-Center");
			setLineWidth(rampLW*1.5);
			drawLine(0, 0, 0, rampW-1 + rampLW); /* Draw full width line at top an bottom */
			drawLine(rampH-1, 0, rampH-1, rampW-1 + rampLW); /* Draw full width line at top an d bottom */
		}
		run("Rotate 90 Degrees Left");
		run("Canvas Size...", "width=" + canvasW + " height=" + canvasH + " position=Center-Left");
		if (dpChoice=="Auto")
			decPlaces = autoCalculateDecPlaces3(rampMin, rampMax, numIntervals);
		else if (dpChoice=="Manual")
			decPlaces=getNumber("Choose Number of Decimal Places", 0);
		else if (dpChoice=="Scientific")
			decPlaces = -1;
		else decPlaces = parseFloat(dpChoice);
		if (parameter=="Object") decPlaces = 0; /* This should be an integer */
		/* draw ticks and values */
		rampOffset = (getHeight-rampH)/2;
		step = rampH;
		if (numLabels>2) step /= (numIntervals);
		stepV = rampRange/numIntervals;
		if (diagnostics) IJ.log ("numIntervals: " + numIntervals + ", step: " + step + ", rampH: " + rampH + ", numLabels: " + numLabels + ", stepV: " + stepV);
		/* Create array of ramp labels that can be used to optimize label length */
		rampLabelString = newArray;
		for (i=0, maxDP=0; i<numLabels; i++) {
			rampLabel = rampMin + i * stepV;
			rampLabelString[i] = d2s(rampLabel, decPlaces);
		}
		/* Ramp number label cleanup */
		for (i=0; i<decPlaces; i++){
			for (nL=0, allEndZeros=true; nL<numLabels; nL++) 
				if (!endsWith(rampLabelString[nL], "0") && indexOf(rampLabelString[nL], ".")>=0) allEndZeros = false;
			for (nL=0; nL<numLabels && allEndZeros; nL++)  if (indexOf(rampLabelString[nL], ".")>=0)
				rampLabelString[nL] = substring(rampLabelString[nL], 0, rampLabelString[nL].length-1);
			for (nL=0, allEndPeriods=true; nL<numLabels; nL++) if (!endsWith(rampLabelString[nL], ".")) allEndPeriods = false;
			for (nL=0; nL<numLabels && allEndPeriods; nL++) rampLabelString[nL] = substring(rampLabelString[nL], 0, rampLabelString[nL].length-1);
			for (nL=0; nL<numLabels && !allEndPeriods; nL++) if (endsWith(rampLabelString[nL], ".")) rampLabelString[nL] = rampLabelString[nL] + "0";
		}
		/* clean up top and bottom zero labels are special cases even in non-auto mode */
		for (i=0; i<numLabels; i=i + numLabels-1)
			if (parseFloat(rampLabelString[i])==0) rampLabelString[i] = "0";
		/* end of ramp number label cleanup */
		setLineWidth(rampLW);
		for (i=0; i<numLabels; i++) {
			yPos = rampH + rampOffset - i*step -1; /* minus 1 corrects for coordinates starting at zero */
			/*Now add overrun text labels at the top and/or bottom of the ramp if the true data extends beyond the ramp range */
			if (i==0 && rampMin>(1.001*arrayMin))
				rampLabelString[i] = fromCharCode(0x2264) + rampLabelString[i];
			if (i==(numLabels-1) && rampMax<(0.999*arrayMax))
				rampLabelString[i] = fromCharCode(0x2265) + rampLabelString[i];
			drawString(rampLabelString[i], rampW + 4*rampLW, yPos + numLabelFontSize/1.5);
			/* major ticks are not optional in this version as they are needed to make sense of the ramp labels */
			if ((i>0) && (i<(numIntervals))) {
				setLineWidth(rampLW);
				drawLine(0, yPos, tickL, yPos);					/* left tick */
				drawLine(rampW-1-tickL, yPos, rampW, yPos);
				drawLine(rampW, yPos, rampW + rampLW, yPos); /* right tick extends over border slightly as subtle cross-tick */
			}
			/* end of ramp major tick drawing */
		}
		setFont(fontName, fontSize, fontStyle);
		/* draw minor ticks */
		if (minorTicks>0) {
			minorTickStep = step/(minorTicks + 1);
			numTick = numLabels + numIntervals * minorTicks - 1; /* no top tick */
			for (i=1; i<numTick; i++) { /* no bottom tick */
				yPos = rampH + rampOffset - i*minorTickStep -1; /* minus 1 corrects for coordinates starting at zero */
				setLineWidth(round(rampLW/4));
				drawLine(0, yPos, tickLR, yPos);					/* left minor tick */
				drawLine(rampW-tickLR-1, yPos, rampW-1, yPos);		/* right minor tick */
			}
		}
		/* end draw minor ticks */
		/* now add lines and the true min and max and for stats if chosen in previous dialog */
		if (rampMinMaxLines || statsRampLines!="No") {
			newImage("label_mask", "8-bit black", getWidth(), getHeight(), 1);
			setColor("white");
			setLineWidth(rampLW);
			minPos = 0; maxPos = rampH; /* to be used in later sd overlap if statement */
			if (rampMinMaxLines) {
				if (rampMin==rampMax) restoreExit("Something terribly wrong with this range!");
				trueMaxFactor = (arrayMax-rampMin)/(rampRange);
				maxPos = rampTBMargin + (rampH * (1 - trueMaxFactor))-1;
				trueMinFactor = (arrayMin-rampMin)/(rampRange);
				minPos = rampTBMargin + (rampH * (1 - trueMinFactor))-1;
				if (trueMaxFactor<1 && maxPos<(rampH - 0.5*fontSR2)) {
					setFont(fontName, fontSR2, fontStyle);
					stringY = round(maxOf(maxPos + 0.75*fontSR2, rampTBMargin + 0.75*fontSR2));
					drawString("Max", round((rampW-getStringWidth("Max"))/2), stringY);
					drawLine(rampLW, maxPos, tickLR, maxPos);
					drawLine(rampW-1-tickLR, maxPos, rampW-rampLW-1, maxPos);
				}
				if (trueMinFactor>0 && minPos>(0.5*fontSR2)) {
					setFont(fontName, fontSR2, fontStyle);
					stringY = round(minOf(minPos + 0.75*fontSR2, rampTBMargin + rampH-0.25*fontSR2));
					drawString("Min", round((rampW-getStringWidth("Min"))/2), stringY);
					drawLine(rampLW, minPos, tickLR, minPos);
					drawLine(rampW-1-tickLR, minPos, rampW-rampLW-1, minPos);
				}
			}
			if (statsRampLines!="No") {
				rampMeanPlusSDFactors = newArray(sIntervalsR);
				rampMeanMinusSDFactors = newArray(sIntervalsR);
				plusSDPos = newArray(sIntervalsR);
				minusSDPos = newArray(sIntervalsR);
				if (statsRampLines=="Ln") {
					rampSD = exp(lnSD);
					rampMeanPlusSDs = expLnMeanPlusSDs;
					rampMeanMinusSDs = expLnMeanMinusSDs;
				}
				else {
					rampSD = arraySD;
					rampMeanPlusSDs = meanPlusSDs;
					rampMeanMinusSDs = meanMinusSDs;
				}
				for (s=0; s<sIntervalsR; s++) {
					rampMeanPlusSDFactors[s] = (rampMeanPlusSDs[s]-rampMin)/rampRange;
					rampMeanMinusSDFactors[s] = (rampMeanMinusSDs[s]-rampMin)/rampRange;
					plusSDPos[s] = rampTBMargin + (rampH * (1 - rampMeanPlusSDFactors[s])) -1;
					minusSDPos[s] = rampTBMargin + (rampH * (1 - rampMeanMinusSDFactors[s])) -1;
				}
				meanFS = 0.9*fontSR2;
				setFont(fontName, meanFS, fontStyle);
				if ((rampMeanPlusSDs[0]>(rampMin + 0.2*rampRange)) && ((rampMeanPlusSDs[0]-rampMin)<=(0.92*rampRange))) {
					drawString("Mean", round((rampW-getStringWidth("Mean"))/2), plusSDPos[0] + 0.75*meanFS);
					drawLine(rampLW, plusSDPos[0], tickLR, plusSDPos[0]);
					drawLine(rampW-1-tickLR, plusSDPos[0], rampW-rampLW-1, plusSDPos[0]);
				}
				else IJ.log("Warning: Mean not drawn on ramp as determined to be to be out of filled ramp range");
				lastDrawnPlusSDPos = plusSDPos[0];
				sPLimit = lengthOf(rampMeanPlusSDFactors)-1; /* should be sIntervalsR but this was a voodoo fix for some issue here */
				sMLimit = lengthOf(rampMeanMinusSDFactors)-1; /* should be sIntervalsR but this was a voodoo fix for some issue here */
				for (s=1; s<sIntervalsR; s++) {
					if ((rampMeanPlusSDFactors[minOf(sPLimit, s)]<=1) && (plusSDPos[s]<=(rampH - fontSR2)) && (abs(plusSDPos[s]-lastDrawnPlusSDPos)>0.75*fontSR2)) {
						setFont(fontName, fontSR2, fontStyle);
						if (rampMinMaxLines) {
							if (plusSDPos[s]<=(maxPos-0.9*fontSR2) || plusSDPos[s]>=(maxPos + 0.9*fontSR2)) { /* prevent overlap with max line */
								drawString(" + " + s + sigmaChar, round((rampW-getStringWidth(" + " + s + sigmaChar))/2), round(plusSDPos[s] + 0.75*fontSR2));
								drawLine(rampLW, plusSDPos[s], tickLR, plusSDPos[s]);
								drawLine(rampW-1-tickLR, plusSDPos[s], rampW-rampLW-1, plusSDPos[s]);
								lastDrawnPlusSDPos = plusSDPos[s];
							}
						}
						else {
							drawString(" + " + s + sigmaChar, round((rampW-getStringWidth(" + " + s + sigmaChar))/2), round(plusSDPos[s] + 0.75*fontSR2));
							drawLine(rampLW, plusSDPos[s], tickLR, plusSDPos[s]);
							drawLine(rampW-1-tickLR, plusSDPos[s], rampW-rampLW-1, plusSDPos[s]);
							lastDrawnPlusSDPos = plusSDPos[s];
						}
						if (rampMeanPlusSDFactors[minOf(sPLimit, minOf(sIntervalsR, s + 1))]>=0.98) s = sIntervalsR;
					}
				}
				lastDrawnMinusSDPos = minusSDPos[0];
				for (s=1; s<sIntervalsR; s++) {
					if ((rampMeanMinusSDFactors[minOf(sPLimit, s)]>0) && (minusSDPos[s]>fontSR2) && (abs(minusSDPos[s]-lastDrawnMinusSDPos)>0.75*fontSR2)) {
						setFont(fontName, fontSR2, fontStyle);
						if (rampMinMaxLines) {
							if ((minusSDPos[s]<(minPos-0.9*fontSR2)) || (minusSDPos[s]>(minPos + 0.9*fontSR2))) { /* prevent overlap with min line */
								drawString("-" + s + sigmaChar, round((rampW-getStringWidth("-" + s + sigmaChar))/2), round(minusSDPos[s] + 0.5*fontSR2));
								drawLine(rampLW, minusSDPos[s], tickLR, minusSDPos[s]);
								drawLine(rampW-1-tickLR, minusSDPos[s], rampW-rampLW-1, minusSDPos[s]);
								lastDrawnMinusSDPos = minusSDPos[s];
							}
						}
						else {
							drawString("-" + s + sigmaChar, round((rampW-getStringWidth("-" + s + sigmaChar))/2), round(minusSDPos[s] + 0.5*fontSR2));
							drawLine(rampLW, minusSDPos[s], tickLR, minusSDPos[s]);
							drawLine(rampW-1-tickLR, minusSDPos[s], rampW-rampLW-1, minusSDPos[s]);
							lastDrawnMinusSDPos = minusSDPos[s];
						}
						if (rampMeanMinusSDs[minOf(sMLimit, minOf(sIntervalsR, s + 1))]<0.93*rampMin) s = sIntervalsR;
					}
				}
			}
			run("Duplicate...", "title=stats_text");
			/* now use a mask to create black outline around white text to stand out against ramp colors */
			selectWindow("label_mask");
			rampOutlineStroke = maxOf(1, round(rampLW/2));
			setThreshold(0, 128);
			setOption("BlackBackground", false);
			run("Convert to Mask");
			selectWindow(tR);
			run("Select None");
			getSelectionFromMask("label_mask");
			getSelectionBounds(maskX, maskY, null, null);
			if (rampOutlineStroke>0) rampOutlineOffset = maxOf(0, (rampOutlineStroke/2)-1);
			setSelectionLocation(maskX + rampOutlineStroke, maskY + rampOutlineStroke); /* Offset selection to create shadow effect */
			run("Enlarge...", "enlarge=" + rampOutlineStroke + " pixel");
			setBackgroundColor(0, 0, 0);
			run("Clear");
			run("Enlarge...", "enlarge=" + rampOutlineStroke + " pixel");
			run("Gaussian Blur...", "sigma=" + rampOutlineStroke);
			run("Select None");
			getSelectionFromMask("label_mask");
			if (offWhiteIntRampLabels) setBackgroundColor(245, 245, 245);  /* set to off-white so that these labels are not transparent when white is set as the transparent layer */
			else setBackgroundColor(255, 255, 255);
			run("Clear");
			run("Select None");
			setBackgroundColor(255, 255, 255);  /* Restore background to white for ramp expansion */
			/* The following steps smooth the interior of the text labels */
			selectWindow("stats_text");
			getSelectionFromMask("label_mask");
			if (selectionType()>=0) run("Make Inverse");
			else restoreExit("Ramp creation: No selection to invert");
			run("Invert");
			run("Select None");
			imageCalculator("Min", tR, "stats_text");
			if (!diagnostics) closeImageByTitle("label_mask");
			if (!diagnostics) closeImageByTitle("stats_text");
			/* reset colors and font */
			setFont(fontName, fontSize, fontStyle);
			setColor(0, 0, 0);
		}
		setColor(0, 0, 0);
		/*	parse symbols in unit and draw final label below ramp */
		selectWindow(tR);
		if ((rampW > maxOf(getStringWidth(rampUnitLabel), getStringWidth(rampParameterLabel))) && !rotLegend) { /* can center align if labels shorter than ramp width */
			if (rampParameterLabel!="") drawString(rampParameterLabel, round((rampW-(getStringWidth(rampParameterLabel)))/2), round(1.5*fontSize));
			if (rampUnitLabel!="") drawString(rampUnitLabel, round((rampW-(getStringWidth(rampUnitLabel)))/2), round(canvasH-0.5*fontSize));
		}
		else { /* need to left align if labels are longer and increase distance from ramp */
			autoCropGuessBackgroundSafe();	/* toggles batch mode */
			getDisplayedArea(null, null, canvasW, canvasH);
			run("Rotate 90 Degrees Left");
			canvasW = getHeight + round(2.5*fontSize);
			if (rampUnitLabel!=""){
				if (unitSeparator=="\(unit\)") rampParameterLabel += " \(" + rampUnitLabel + "\)";
				else if (unitSeparator=="[unit]") rampParameterLabel += " [" + rampUnitLabel + "]";
				else if (unitSeparator=="{unit}") rampParameterLabel += " {" + rampUnitLabel + "}";
				else rampParameterLabel += ", " + rampUnitLabel;
			}
			run("Canvas Size...", "width=" + canvasH + " height=" + canvasW + " position=Bottom-Center");
			if (rampParameterLabel!=""){
				rampParLabL = getStringWidth(rampParameterLabel);
				if (rampParLabL>0.9*canvasH){
					modFSRLab = 0.9*fontSize*canvasH/rampParLabL;
					setFont(fontName, modFSRLab, fontStyle);
					drawString(rampParameterLabel, round((canvasH-(getStringWidth(rampParameterLabel)))/2), round(1.5*fontSize));
					setFont(fontName, fontSize, fontStyle);
				}
				else drawString(rampParameterLabel, round((canvasH-(getStringWidth(rampParameterLabel)))/2), round(1.5*fontSize));
			}
			run("Rotate 90 Degrees Right");
		}
		autoCropGuessBackgroundSafe();	/* toggles batch mode */
		/* add padding to legend box - better than expanding crop selection as is adds padding to all sides */
		getDisplayedArea(null, null, canvasW, canvasH);
		canvasW += round(imageWidth/150);
		canvasH += round(imageHeight/150);
		run("Canvas Size...", "width=" + canvasW + " height=" + canvasH + " position=Center");
		/*
			iterate through the ROI Manager list and colorize ROIs
		*/
		selectImage(orID);
		/* iterate through the ROI Manager list and colorize ROIs */
		roiManager("Deselect");
		roiManager("Show All");
		roiManager("Show None");
		RoiManager.useNamesAsLabels(true);
		labelSettings =  "color=" + labelColor + " font=" + labelFontSize + " show use";  /* Note the # values and transparency do not appear to be supported */
		if (labelBold) labelSettings += " bold";
		if (labelBkgrd) labelSettings += " draw";
		run("Labels...", labelSettings);
		if (roiNameRestore){
			oldROINames = newArray;
			for (i=0; i<nROIs; i++){
				roiManager("select", i);
				oldROINames[i] = Roi.getName();
			}
		}
		if (subset){
			/* clear to full transparency area and line colors from any previous run */
			for (i=0; i<nROIs; i++) { /* Needs to be ALL ROIs */
				roiManager("select", i);
				roiManager("Set Line Width", 0);
				roiManager("Set Color", "none");
				roiManager("Set Fill Color", "#00ffffff");
			}
			if (!selectionExists) { /* Starts the creation of a selection area for later cropping */
				selPosStartX = imageWidth;
				selPosStartY = imageHeight;
				selPosEndX = 0;
				selPosEndY = 0;
			}
		}
		for (countNaN=0, i=0; i<iROIs.length; i++) {
			if (isNaN(values[i])) countNaN++;
			if (!revLut) {
				if (values[i]<=rampMin)
				  lutIndex = 0;
				else if (values[i]>rampMax)
				  lutIndex = 255;
				else
				  lutIndex = round(255 * (values[i] - rampMin) / (rampRange));
			}
			else {
				if (values[i]<=rampMin)
					lutIndex = 255;
				else if (values[i]>rampMax)
					lutIndex = 0;
				else
					lutIndex = round(255 * (rampMax - values[i]) / (rampRange));
	 		}
			roiManager("select", iROIs[i]);
			if (stroke>0) {
				roiManager("Set Line Width", stroke);
				roiManager("Set Color", alpha + roiColors[lutIndex]);
			} else{
				roiManager("Set Line Width", 0);
				roiManager("Set Color", "#00ffffff");
				roiManager("Set Fill Color", alpha + roiColors[lutIndex]);
			}
			if (subset && !selectionExists){ /* For the creation of a selection area for later cropping */
				getSelectionBounds(x, y, width, height);
				selPosStartX = minOf(selPosStartX, x);
				selPosStartY = minOf(selPosStartY, y);
				selPosEndX = maxOf(selPosEndX, x + width);
				selPosEndY = maxOf(selPosEndY, y + height);
			}
		}
		if (subset && !selectionExists){
			originalSelEWidth = selPosEndX - selPosStartX;
			originalSelEHeight = selPosEndY - selPosStartY;
		}
	}
	else {
		IJ.log("Stroke/fill option set to labels only , we are headed into untested territory   D:");
		decPlaces = autoCalculateDecPlaces3(rampMin, rampMax, numIntervals);
	}
	/*
	End of object coloring
	*/
	/* recombine units and labels that were used in Ramp */
	paraLabel = parameterLabel;
	paraLabelExp = parameterLabelExp;
	if (unitLabel!=""){
		paraLabel = parameterLabel + ", " + unitLabel;
		paraLabelExp = parameterLabelExp + ", " + unitLabel;
	}
	if (!addLabels) {
		selectWindow(tN);
		roiManager("show all with labels");
		run("Flatten"); /* creates an RGB copy of the image with color coded objects or not */
	}
	else {
		for (countNaN=0, i=0; i<iROIs.length; i++) {
			roiManager("select", iROIs[i]);
			labelValue = values[i];
			labelString = d2s(labelValue, decPlaces); /* Reduce decimal places for labeling (move these two lines to below the labels you prefer) */
			labelString = removeTrailingZerosAndPeriod(labelString); /* Remove trailing zeros and periods */
			roiManager("Rename", labelString); /* label roi with feature value */
		}
		RoiManager.useNamesAsLabels("true");
		roiManager("show all with labels");
		run("Flatten");
	}
	rename(tN + "_" + parameter + "-coded");
	tNC = getTitle();
/* Image and Ramp combination dialog */
	roiManager("Deselect");
	run("Select None");
	Dialog.create("Combine labeled image and color-code legend?");
		comboChoice = newArray("No", "Image + color-code legend", "Auto-cropped image + color-code legend", "Manually cropped image + color-code legend");
		Dialog.addRadioButtonGroup("Combine labeled image with color-code legend?", comboChoice, 5, 1, comboChoice[1]) ;
	Dialog.show();
		createCombo = Dialog.getRadioButton;
	if (createCombo!="No") {
		if (indexOf(createCombo, "cropped")>0){
			if (is("Batch Mode")==true) setBatchMode("exit & display");	/* toggle batch mode off */
			selectWindow(tNC);
			run("Duplicate...", "title=" + tNC + "_crop");
			cropID = getImageID;
			run("Select Bounding Box (guess background color)");
			run("Enlarge...", "enlarge=" + round(imageHeight*0.02) + " pixel"); /* Adds a 2% margin */
			if (startsWith(createCombo, "Manual")) {
				if (subset) makeRectangle(selPosStartX, selPosStartY, originalSelEWidth, originalSelEHeight);
				else {
					getSelectionBounds(xA, yA, widthA, heightA);
					makeRectangle(maxOf(2, xA), maxOf(2, yA), minOf(imageWidth-4, widthA), minOf(imageHeight-4, heightA));
				}
				setTool("rectangle");
				title = "Crop Location for Combined Image";
				msg = "1. Select the area that you want to crop to. 2. Click on OK";
				waitForUser(title, msg);
			}
			if (!diagnostics || is("Batch Mode")==false) setBatchMode(true);	/* toggle batch mode back on */
			selectImage(cropID);
			if(selectionType>=0) run("Crop");
			else IJ.log("Combination with cropped image desired by no crop made");
			run("Select None");
			if (!diagnostics) closeImageByTitle(tNC);
			rename(tNC);
			imageHeight = getHeight();
			imageWidth = getWidth();
		}
		if (canvasH>imageHeight){
			rampScale = imageHeight/canvasH;
			selectWindow(tR);
			run("Scale...", "x=" + rampScale + " y=" + rampScale + " interpolation=Bicubic average create title=scaled_ramp");
			if (!diagnostics) closeImageByTitle(tR);
			rename(tR);
			canvasH = getHeight(); /* update ramp height */
			canvasW = getWidth(); /* update ramp height */
		}
		rampMargin = maxOf(2, imageWidth/500);
		rampSelW = canvasW + rampMargin;
		comboW = imageWidth + rampSelW;
		if (is("Batch Mode")==true) setBatchMode("exit & display");	/* toggle batch mode off */
		selectWindow(tNC);
		run("Canvas Size...", "width=" + comboW + " height=" + imageHeight + " position=Top-Left");
		selectWindow(tR);
		wait(5);
		Image.copy;
		selectWindow(tNC);
		wait(5);
		Image.paste(imageWidth + maxOf(2, imageWidth/500), round((imageHeight-canvasH)/2));
		rename(tNC + " + legend");
		if ((imageDepth==8 && lut=="Grays") || is("grayscale")) run("8-bit"); /* restores gray if all gray settings */
		closeImageByTitle(tR);
	}
	if (subset){
		timeStamp = getDateTimeCode();
		timeStamp = substring(timeStamp, 0, lastIndexOf(timeStamp, "m"));
		roiPath = tPath + tNL + "_" + iROIs.length + "_" + timeStamp + "_" + "SelectedROIs.zip";
		roiManager("select", iROIs); /* iROIs ? */
		roiManager("save selected", roiPath);
		roiManager("Deselect");
		roiListPath = tPath + tNL + "_" + iROIs.length + "_" + timeStamp + "_" + "SelectedROIs.csv";
		File.saveString(subsetROIs, roiListPath);
		call("ij.Prefs.set", ascPrefsKey + "roiListPath", roiListPath);
	}
	finalID = getImageID();
	if (selectionExists){
		/* Restore original selection to original image */
		if (selType==0 || selType==1){
			selectImage(orID);
			roiManager("show none");
			if (selType==0) makeRectangle(selPosStartX, selPosStartY, originalSelEWidth, originalSelEHeight);
			else makeOval(selPosStartX, selPosStartY, originalSelEWidth, originalSelEHeight);
			selectImage(finalID);
		}
	}
	if (roiNameRestore){
		for (i=0; i<nROIs; i++){
			roiManager("select", i);
			roiManager("Rename", oldROINames[i]);
		}
		roiManager("Deselect");
	}
	selectImage(finalID);
	roiManager("Show All without labels");
	roiManager("Show None");
	setBatchMode("exit & display");
	restoreSettings;
	memFlush(200);
	showStatus(macroL + " macro finished", "flash green");
	beep(); wait(300); beep(); wait(300); beep();
	/* End of ROI Color Coder with ROI Labels */
}
	/*
		   ( 8(|)	( 8(|)	Functions	@@@@@:-)	@@@@@:-)
   */

 	function autoCalculateDecPlaces3(min, max, intervals){
		/* v210428 3 variable version */
		step = (max-min)/intervals;
		stepSci = d2s(step, -1);
		iExp = indexOf(stepSci, "E");
		stepExp = parseInt(substring(stepSci, iExp + 1));
		if (stepExp<-7) dP = -1; /* Scientific Notation */
		else if (stepExp<0) dP = -1 * stepExp + 1;
		else if (stepExp>=5) dP = -1; /* Scientific Notation */
		else if (stepExp>=2) dP = 0;
		else if (stepExp>=0) dP = 1;
		return dP;
	}
	function autoCropGuessBackgroundSafe() {
		if (is("Batch Mode")==true) setBatchMode(false);	/* toggle batch mode off */
		run("Auto Crop (guess background color)"); /* not reliable in batch mode */
		if (is("Batch Mode")==false) setBatchMode(true);	/* toggle batch mode back on */
	}
	function checkForPlugin(pluginName) {
		/* v161102 changed to true-false
			v180831 some cleanup
			v210429 Expandable array version
			v220510 Looks for both class and jar if no extension is given
			v220818 Mystery issue fixed, no longer requires restoreExit	*/
		pluginCheck = false;
		if (getDirectory("plugins") == "") IJ.log("Failure to find any plugins!");
		else {
			pluginDir = getDirectory("plugins");
			if (lastIndexOf(pluginName, ".")==pluginName.length-1) pluginName = substring(pluginName, 0, pluginName.length-1);
			pExts = newArray(".jar", ".class");
			knownExt = false;
			for (j=0; j<lengthOf(pExts); j++) if(endsWith(pluginName, pExts[j])) knownExt = true;
			pluginNameO = pluginName;
			for (j=0; j<lengthOf(pExts) && !pluginCheck; j++){
				if (!knownExt) pluginName = pluginName + pExts[j];
				if (File.exists(pluginDir + pluginName)) {
					pluginCheck = true;
					showStatus(pluginName + "found in: " + pluginDir);
				}
				else {
					pluginList = getFileList(pluginDir);
					subFolderList = newArray;
					for (i=0, subFolderCount=0; i<lengthOf(pluginList); i++) {
						if (endsWith(pluginList[i], "/")) {
							subFolderList[subFolderCount] = pluginList[i];
							subFolderCount++;
						}
					}
					for (i=0; i<lengthOf(subFolderList); i++) {
						if (File.exists(pluginDir + subFolderList[i] + "\\" + pluginName)) {
							pluginCheck = true;
							showStatus(pluginName + " found in: " + pluginDir + subFolderList[i]);
							i = lengthOf(subFolderList);
						}
					}
				}
			}
		}
		return pluginCheck;
	}
	function checkForPluginNameContains(pluginNamePart) {
		/* v180831 1st version to check for partial names so avoid versioning problems
			...
			v220722 Uses File.separator and adds .class
			v230912 This version is case insensitive and does NOT require restoreExit.
			NOTE: underlines are NOT converted to spaces in names */
		pluginCheck = false;
		pluginNamePart = toLowerCase(pluginNamePart);
		fS = File.separator;
		pluginDir = getDirectory("plugins");
		if (pluginDir == "") IJ.log("Failure to find any plugins!");
		else {
			pluginFolderList = getFileList(pluginDir);
			subFolderList = newArray();
			pluginList = newArray();
			for (l=0; l<pluginFolderList.length; l++){
				if (endsWith(pluginFolderList[l], fS)) subFolderList = Array.concat(subFolderList, pluginFolderList[l]);
				else if (endsWith(pluginFolderList[l], "/")) subFolderList = Array.concat(subFolderList, pluginFolderList[l]); /* File.separator does not seem to be working here */
				else if (endsWith(toLowerCase(pluginFolderList[l]), ".jar") || endsWith(toLowerCase(pluginFolderList[l]), ".class")) pluginList = Array.concat(pluginList, toLowerCase(pluginFolderList[l]));
			}
			/* First check root plugin folder */
			for (i=0; i<lengthOf(pluginList) && !pluginCheck; i++) {
				if (indexOf(pluginList[i], pluginNamePart)>=0) pluginCheck = true;
			}
			/* If not in the root try the subfolders */
			if (!pluginCheck) {
				for (i=0; i<subFolderList.length && !pluginCheck; i++) {
					subFolderPluginList = getFileList(pluginDir + subFolderList[i]);
					for (k=0; k<subFolderPluginList.length; k++) subFolderPluginList[k] = toLowerCase(subFolderPluginList[k]);
					for (j=0; j<subFolderPluginList.length && !pluginCheck; j++) {
						if (endsWith(subFolderPluginList[j], ".jar") || endsWith(subFolderPluginList[j], ".class"))
							if (indexOf(subFolderPluginList[j], pluginNamePart)>=0) pluginCheck = true;
					}
				}
			}
		}
		return pluginCheck;
	}
	function checkForResults() {
		/*	v220706:	More friendly to Results tables not called "Results"
			v230720:	Does not initially open ROI Manager.
		*/
		if (isOpen("ROI Manager")){
			nROIs = roiManager("count");
			if (nROIs==0) close("ROI Manager");
		}
		else nROIs = 0;
		tSize = Table.size;
		if (tSize>0) oTableTitle = Table.title;
		nRes = nResults;
		if (nRes==0 && tSize>0){
			oTableTitle = Table.title;
			renameTable = getBoolean("There is no Results table but " + oTableTitle + "has " + tSize + "rows:", "Rename to Results", "No, I will take may chances");
			if (renameTable) {
				Table.rename(oTableTitle, "Results");
				nRes = nResults;
			}
		}
		if (getInfo("window.type")!="ResultsTable" && nRes<=0)	{
			Dialog.create("No Results to Work With");
			Dialog.addMessage("This macro requires a Results table to analyze.\n \nThere are " + nRes + " results.\nThere are " + nROIs + " ROIs.");
			Dialog.addRadioButtonGroup("No Results to Work With:", newArray("Run Analyze-particles to generate table", "Import Results table", "Exit"), 2, 1, "Run Analyze-particles to generate table");
			Dialog.show();
			actionChoice = Dialog.getRadioButton();
			if (actionChoice=="Exit") restoreExit("Goodbye, your previous setting will be restored.");
			else if (actionChoice=="Run Analyze-particles to generate table"){
				if (roiManager("count")!=0) {
					roiManager("deselect")
					roiManager("delete");
				}
				setOption("BlackBackground", false);
				run("Analyze Particles..."); /* Let user select settings */
			}
			else {
				open(File.openDialog("Select a Results Table to import"));
				Table.rename(Table.title, "Results");
			}
		}
	}
	function checkForRoiManager() {
		/* v161109 adds the return of the updated ROI count and also adds dialog if there are already entries just in case . .
			v180104 only asks about ROIs if there is a mismatch with the results
			v190628 adds option to import saved ROI set
			v210428	include thresholding if necessary and color check
			v211108 Uses radio-button group.
			NOTE: Requires ASC restoreExit function, which assumes that saveSettings has been run at the beginning of the macro
			v220706: Table friendly version
			v220816: Enforces non-inverted LUT as well as white background and fixes ROI-less analyze.  Adds more dialog labeling.
			v230126: Does not change foreground or background colors.
			v230130: Cosmetic improvements to dialog.
			v230720: Does not initially open ROI Manager.
			v231211: Adds option to measure ROIs.
			*/
		functionL = "checkForRoiManager_v231211";
		if (isOpen("ROI Manager")){
			nROIs = roiManager("count");
			if (nROIs==0) close("ROI Manager");
		}
		else nROIs = 0;
		nRes = nResults;
		tSize = Table.size;
		if (nRes==0 && tSize>0){
			oTableTitle = Table.title;
			renameTable = getBoolean("There is no Results table but " + oTableTitle + "has " + tSize + "rows:", "Rename to Results", "No, I will take may chances");
			if (renameTable) {
				Table.rename(oTableTitle, "Results");
				nRes = nResults;
			}
		}
		if(nROIs==0 || nROIs!=nRes){
			Dialog.create("ROI mismatch options: " + functionL);
				Dialog.addMessage("This macro requires that all objects have been loaded into the ROI manager.\n \nThere are   " + nRes + "   results.\nThere are   " + nROIs + "   ROIs", 12, "#782F40");
				mismatchOptions = newArray();
				if (nROIs==0) mismatchOptions = Array.concat(mismatchOptions, "Import a saved ROI list");
				else mismatchOptions = Array.concat(mismatchOptions, "Replace the current ROI list with a saved ROI list");
				if (nRes==0) mismatchOptions = Array.concat(mismatchOptions, "Import a Results Table \(csv\) file");
				else mismatchOptions = Array.concat(mismatchOptions, "Clear Results Table and import saved csv");
				if (nRes==0 && nROIs>0) mismatchOptions = Array.concat(mismatchOptions, "Measure all the ROIs");
				mismatchOptions = Array.concat(mismatchOptions, "Clear ROI list and Results Table and reanalyze \(overrides above selections\)");
				if (!is("binary")) Dialog.addMessage("The active image is not binary, so it may require thresholding before analysis");
				mismatchOptions = Array.concat(mismatchOptions, "Get me out of here, I am having second thoughts . . .");
				Dialog.addRadioButtonGroup("How would you like to proceed:_____", mismatchOptions, lengthOf(mismatchOptions), 1, mismatchOptions[0]);
			Dialog.show();
				mOption = Dialog.getRadioButton();
			if (startsWith(mOption, "Sorry")) restoreExit("Sorry this did not work out for you.");
			if (startsWith(mOption, "Replace")){
				roiPath = File.openDialog("Select ROI set to open");
				if (File.exists(roiPath)){
					roiManager("reset");
					roiManager("Open", roiPath);
				}
			}
			else if (startsWith(mOption, "Measure all")) {
				roiManager("Deselect");
				roiManager("Measure");
				nRes = nResults;
			}	
			else if (startsWith(mOption, "Clear ROI list and Results Table and reanalyze")) {
				if (!is("binary")){
					if (is("grayscale") && bitDepth()>8){
						proceed = getBoolean(functionL + ": Image is grayscale but not 8-bit, convert it to 8-bit?", "Convert for thresholding", "Get me out of here");
						if (proceed) run("8-bit");
						else restoreExit(functionL + ": Goodbye, perhaps analyze first?");
					}
					if (bitDepth()==24){
						colorThreshold = getBoolean(functionL + ": Active image is RGB, so analysis requires thresholding", "Color Threshold", "Convert to 8-bit and threshold");
						if (colorThreshold) run("Color Threshold...");
						else run("8-bit");
					}
					if (!is("binary")){
						/* Quick-n-dirty threshold if not previously thresholded */
						getThreshold(t1, t2);
						if (t1==-1)  {
							run("Auto Threshold", "method=Default");
							run("Convert to Mask");
							if (is("Inverting LUT")) run("Invert LUT");
							if(getPixel(0, 0)==0) run("Invert");
						}
					}
				}
				if (is("Inverting LUT"))  run("Invert LUT");
				/* Make sure black objects on white background for consistency */
				cornerPixels = newArray(getPixel(0, 0), getPixel(0, 1), getPixel(1, 0), getPixel(1, 1));
				Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
				if (cornerMax!=cornerMin) restoreExit("Problem with image border: Different pixel intensities at corners");
				/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
					i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
				if (cornerMean==0) run("Invert");
				if (isOpen("ROI Manager"))	roiManager("reset");
				if (isOpen("Results")) {
					selectWindow("Results");
					run("Close");
				}
				// run("Analyze Particles..."); /* Letting users select settings does not create ROIs  ¯\_(?)_/¯ */
				run("Analyze Particles...", "display clear include add");
				nROIs = roiManager("count");
				nRes = nResults;
				if (nResults!=roiManager("count"))
					restoreExit(functionL + ": Results \(" + nRes + "\) and ROI Manager \(" + nROIs + "\) counts still do not match!");
			}
			else {
				if (startsWith(mOption, "Import a saved ROI")) {
					if (isOpen("ROI Manager"))	roiManager("reset");
					msg = functionL + ": Import ROI set \(zip file\), click \"OK\" to continue to file chooser";
					showMessage(msg);
					pathROI = File.openDialog(functionL + ": Select an ROI file set to import");
                    roiManager("open", pathROI);
				}
				if (startsWith(mOption, "Import a Results")){
					if (isOpen("Results")) {
						selectWindow("Results");
						run("Close");
					}
					msg = functionL + ": Import Results Table: Click \"OK\" to continue to file chooser";
					showMessage(msg);
					open(File.openDialog(functionL + ": Select a Results Table to import"));
					Table.rename(Table.title, "Results");
				}
			}
		}
		nROIs = roiManager("count");
		if (nROIs==0) close("ROI Manager");
		nRes = nResults; /* Used to check for ROIs:Results mismatch */
		if(nROIs==0 || nROIs!=nRes)
			restoreExit(functionL + ": Goodbye, there are " + nROIs + " ROIs and " + nRes + " results; your previous settings will be restored.");
		return roiManager("count"); /* Returns the new count of entries */
	}
	function checkForUnits() {  /* Generic version
		/* v161108 (adds inches to possible reasons for checking calibration)
		 v170914 Radio dialog with more information displayed
		 v200925 looks for pixels unit too; v210428 just adds function label
		NOTE: REQUIRES ASC restoreExit function which requires previous run of saveSettings		 */
		functionL = "checkForUnits_v210428";
		getPixelSize(unit, pixelWidth, pixelHeight);
		if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="" || unit=="inches" || unit=="pixels"){
			Dialog.create("Suspicious Units: " + functionL);
			rescaleChoices = newArray("Define new units for this image", "Use current scale", "Exit this macro");
			rescaleDialogLabel = "pixelHeight = " + pixelHeight + ", pixelWidth = " + pixelWidth + ", unit = " + unit + ": what would you like to do?";
			Dialog.addRadioButtonGroup(rescaleDialogLabel, rescaleChoices, 3, 1, rescaleChoices[0]) ;
			Dialog.show();
			rescaleChoice = Dialog.getRadioButton;
			if (rescaleChoice==rescaleChoices[0]) run("Set Scale...");
			else if (rescaleChoice==rescaleChoices[2]) restoreExit("Goodbye");
		}
	}
	function cleanLabel(string) {
		/*  ImageJ macro default file encoding (ANSI or UTF-8) varies with platform so non-ASCII characters may vary: hence the need to always use fromCharCode instead of special characters.
		v180611 added "degreeC"
		v200604	fromCharCode(0x207B) removed as superscript hyphen not working reliably
		v220630 added degrees v220812 Changed Ångström unit code
		v231005 Weird Excel characters added, micron unit correction, "sup" abbreviation expansion */
		string= replace(string, "\\^2", fromCharCode(178)); /* superscript 2 */
		string= replace(string, "\\^3", fromCharCode(179)); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, "\\^-" + fromCharCode(185), "-" + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-" + fromCharCode(178), "-" + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "\\^-^1", "-" + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-^2", "-" + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "\\^-1", "-" + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-2", "-" + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "sup2", fromCharCode(178)); /* superscript 2 */
		string= replace(string, "sup3", fromCharCode(179)); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, "sup-1", "-" + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "sup-2", "-" + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "sup-3", "-" + fromCharCode(179)); /* superscript -3 */
		string= replace(string, "(?<![A-Za-z0-9])u(?=m)", fromCharCode(181)); /* micron units */
		string= replace(string, "\\b[aA]ngstrom\\b", fromCharCode(0x212B)); /* Ångström unit symbol */
		string= replace(string, "  ", " "); /* Replace double spaces with single spaces */
		string= replace(string, "_", " "); /* Replace underlines with space as thin spaces (fromCharCode(0x2009)) not working reliably  */
		string= replace(string, "px", "pixels"); /* Expand pixel abbreviation */
		string= replace(string, "degreeC", fromCharCode(0x00B0) + "C"); /* Degree symbol for dialog boxes */
		// string = replace(string, " " + fromCharCode(0x00B0), fromCharCode(0x2009) + fromCharCode(0x00B0)); /* Replace normal space before degree symbol with thin space */
		// string= replace(string, " °", fromCharCode(0x2009) + fromCharCode(0x00B0)); /* Replace normal space before degree symbol with thin space */
		string= replace(string, "sigma", fromCharCode(0x03C3)); /* sigma for tight spaces */
		string= replace(string, "plusminus", fromCharCode(0x00B1)); /* plus or minus */
		string= replace(string, "degrees", fromCharCode(0x00B0)); /* plus or minus */
		if (indexOf(string, "mý")>1) string = substring(string, 0, indexOf(string, "mý")-1) + getInfo("micrometer.abbreviation") + fromCharCode(178);
		return string;
	}
	function closeImageByTitle(windowTitle) {  /* Cannot be used with tables */
		/* v181002: reselects original image at end if open
		   v200925: uses "while" instead of if so it can also remove duplicates
		   v230411:	checks to see if any images open first.
		*/
		if(nImages>0){
			oIID = getImageID();
			while (isOpen(windowTitle)) {
				selectWindow(windowTitle);
				close();
			}
			if (isOpen(oIID)) selectImage(oIID);
		}
	}
	function createConvolverMatrix(effect, thickness){
		/* v230413: 1st version PJL  Effects assumed: "Recessed or Raised" */
		matrixText = "";
		matrixSize = maxOf(3, (1 + 2*round(thickness/10)));
		matrixLC = matrixSize -1;
		matrixCi = matrixSize/2 - 0.5;
		mFact = 1/(matrixSize-1);
		for(y=0, c=0;y<matrixSize;y++){
			for(x=0;x<matrixSize;x++){
				if(x!=y){
					matrixText +=  " 0";
					if (x==matrixLC) matrixText +=  "\n";
				} 
				else {
					if (x==matrixCi) matrixText +=  " 1";
					else if (effect=="raised"){  /* Otherwise assumed to be 'recessed' */
						if (x<matrixCi) matrixText +=  " -" + mFact;
						else matrixText +=  " " + mFact;
					} 
					else {
						if (x>matrixCi) matrixText +=  " -" + mFact;
						else matrixText +=  " " + mFact;				
					}
				}
			}
		}
		matrixText +=  "\n";
		return matrixText;
	}
	function createShadowDropFromMask7Safe(mask, oShadowDrop, oShadowDisp, oShadowBlur, oShadowDarkness, oStroke) {
		/* Requires previous run of: imageDepth = bitDepth();
		because this version works with different bitDepths
		v161115 calls five variables: drop, displacement blur and darkness
		v180627 adds mask label to variables
		v230405	resets background color after application
		v230418 removed '&'s		*/
		showStatus("Creating drop shadow for labels . . . ");
		newImage("shadow", "8-bit black", imageWidth, imageHeight, 1);
		getSelectionFromMask(mask);
		getSelectionBounds(selMaskX, selMaskY, selMaskWidth, selMaskHeight);
		setSelectionLocation(selMaskX + oShadowDisp, selMaskY + oShadowDrop);
		orBG = Color.background;
		Color.setBackground("white");
		if (oStroke>0) run("Enlarge...", "enlarge=" + oStroke + " pixel"); /* Adjust shadow size so that shadow extends beyond stroke thickness */
		run("Clear");
		run("Select None");
		if (oShadowBlur>0) {
			run("Gaussian Blur...", "sigma=" + oShadowBlur);
			run("Unsharp Mask...", "radius=" + oShadowBlur + " mask=0.4"); /* Make Gaussian shadow edge a little less fuzzy */
		}
		/* Now make sure shadow or glow does not impact outline */
		getSelectionFromMask(mask);
		if (oStroke>0) run("Enlarge...", "enlarge=" + oStroke + " pixel");
		Color.setBackground("black");
		run("Clear");
		run("Select None");
		/* The following are needed for different bit depths */
		if (imageDepth==16 || imageDepth==32) run(imageDepth + "-bit");
		run("Enhance Contrast...", "saturated=0 normalize");
		divider = (100 / abs(oShadowDarkness));
		run("Divide...", "value=" + divider);
		Color.setBackground(orBG);
	}
	function expandLabel(str) {  /* Expands abbreviations typically used for compact column titles
		v200604	fromCharCode(0x207B) removed as superscript hyphen not working reliably
		v211102-v211103  Some more fixes and updated to match latest extended geometries
		v220808 replaces ° with fromCharCode(0x00B0)
		v230106 Added a few separation abbreviations
		v230109 Reorganized to prioritize all standard IJ labels and make more consistent. Also introduced string.replace and string.substring */
		requires("1.52t"); /* for string.replace */
		/* standard IJ labels */
		if (str=="Angle") str = "Ellipse Angle";
		else if (str=="AR") str = "Aspect Ratio \(ellipse fit\)";
		else if (str=="AR_Box") str = "Aspect Ratio \(bounding rectangle\)";
		else if (str=="AR_Feret") str = "Aspect Ratio \(Feret\)";
		else if (str=="BX") str = "Bounding Rectangle X Start";
		else if (str=="BY") str = "Bounding Rectangle Y Start";
		else if (str=="Circ.") str = "Circularity ";
		else if (str=="Elongation") str = "Elongation \(of bounding rectangle\)";
		else if (str=="Feret") str = "Feret's Diameter";
		else if (str=="FeretX") str = "Feret X Start";
		else if (str=="FeretX2") str = "Feret X End";
		else if (str=="FeretY") str = "Feret Y Start";
		else if (str=="FeretY2") str = "Feret Y End";
		else if (str=="Heigth") str = "Bounding Rectangle Height";
		else if (str=="Major") str = "Major Ellipse Axis Length";
		else if (str=="Minor") str = "Minor Ellipse Axis Length";
		else if (str=="MinFeret") str = "Minimum Feret's Diameter";
		else if (str=="MinFeretX") str = "Minimum Feret Start \(x\)";
		else if (str=="MinFeretY") str = "Minimum Feret Start \(y\)";
		else if (str=="MinFeretX2") str = "Minimum Feret End \(x\)";
		else if (str=="MinFeretY2") str = "Minimum Feret End \(y\)";
		else if (str=="Perim.") str = "Perimeter ";
		else if (str=="Round") str = "Roundness \(from area and major ellipse axis\)";
		else if (str=="Rnd_Feret") str = "Roundness \(from maximal Feret's diameter\)";
		else if (str=="Sqr_Diag_A") str = "Diagonal of Square \(from area\)";
		else if (str=="X") str = "Centroid \(x\)";
		else if (str=="Y") str = "Centroid \(y\)";
		else { /* additional ASC geometries */
			str = str.replace(fromCharCode(0x00B0), "degrees");
			str = str.replace("0-90_degrees", "0-90" + fromCharCode(0x00B0)); /* An exception to the above*/
			str = str.replace("0-90degrees", "0-90" + fromCharCode(0x00B0)); /* An exception to the above*/
			str = str.replace("_cAR", "\(Corrected by Aspect Ratio\) ");
			str = str.replace("AR_", "Aspect Ratio: ");
			str = str.replace("BoxH", "Bounding Rectangle Height ");
			str = str.replace("BoxW", "Bounding Rectangle Width ");
			str = str.replace("Cir_to_El_Tilt", "Circle Tilt \(tilt of curcle to match measured ellipse\) ");
			str = str.replace(" Crl ", " Curl ");
			str = str.replace("Compact_Feret", "Compactness \(from Feret axis\) ");
			str = str.replace("Da_Equiv", "Diameter \(from circle area\) ");
			str = str.replace("Dp_Equiv", "Diameter \(from circle perimeter\) ");
			str = str.replace("Dsph_Equiv", "Diameter \(from spherical Feret diameter\) ");
			str = str.replace("Da", "Diameter \(from circle area\) ");
			str = str.replace("Dp", "Diameter \(from circle perimeter\) ");
			str = str.replace("equiv", "Equivalent ");
			str = str.replace("FeretAngle", "Feret's Angle ");
			str = str.replace("Feret's Angle 0to90", "Feret's Angle \(0-90" + fromCharCode(0x00B0) + "\)"); /* fixes a precious labelling inconsistency */
			str = str.replace("Fbr", "Fiber ");
			str = str.replace("FiberThAnn", "Fiber Thickness \(from annulus\) ");
			str = str.replace("FiberLAnn", "Fiber Length (\from annulus\) ");
			str = str.replace("FiberLR", "Fiber Length R ");
			str = str.replace("HSFR", "Hexagon Shape Factor Ratio ");
			str = str.replace("HSF", "Hexagon Shape Factor ");
			str = str.replace("Hxgn_", "Hexagon: ");
			str = str.replace("Intfc_D", "Interfacial Density ");
			str = str.replace("MinSepNNROI", "Minimum Separation NN ROI ");
			str = str.replace("MinSepROI", "Minimum ROI Separation ");
			str = str.replace("MinSepThisROI", "Minimum Separation this ROI ");
			str = str.replace("MinSep", "Minimum Separation ");
			str = str.replace("NN", "Nearest Neighbor ");
			str = str.replace("ObjectN", "Object Number ");
			str = str.replace("Perim.", "Perimeter ");
			if (indexOf(str, "Perimeter")!=indexOf(str, "Perim")) str.replace("Perim", "Perimeter ");
			str = str.replace("Perimetereter", "Perimeter "); /* just in case above failed */
			str = str.replace("Snk", "\(Snake\) ");
			str = str.replace("Raw Int Den", "Raw Interfacial Density ");
			str = str.replace("Rndnss", "Roundness ");
			str = str.replace("Rnd_", "Roundness: ");
			str = str.replace("Rss1", "/(Russ Formula 1/) ");
			str = str.replace("Rss1", "/(Russ Formula 2/) ");
			str = str.replace("Sqr_", "Square: ");
			str = str.replace("Squarity_AP", "Squarity \(from area and perimeter\) ");
			str = str.replace("Squarity_AF", "Squarity \(from area and Feret\) ");
			str = str.replace("Squarity_Ff", "Squarity \(from Feret\) ");
			str = str.replace(" Th ", " Thickness ");
			str = str.replace("ThisROI", " this ROI ");
			str = str.replace("Vol_", "Volume: ");
			if(str=="Width") str = "Bounding Rectangle Width";
			str = str.replace("XM", "Center of Mass \(x\)");
			str = str.replace("XY", "Center of Mass \(y\)");
			str = str.replace(fromCharCode(0x00C2), ""); /* Remove mystery Â */
			str = str.replace(fromCharCode(0x2009), " ");
		}
		while (indexOf(str, "_")>=0) str = str.replace("_", " ");
		while (indexOf(str, "  ")>=0) str = str.replace("  ", " ");
		while (endsWith(str, " ")) str = str.substring(0, lengthOf(str)-1);
		return str;
	}
	function fancyTextOverImage2(fontColor, outlineColor, shadowDrop, shadowDisp, shadowBlur, shadowDarkness, outlineStroke, effect) { /* Place text over image in a way that stands out; requires original "workingImage" and "textImage"
		Requires: functions: createShadowDropFromMask7Safe
		requires createConvolverMatrix function
		v230414-20
		*/
		selectWindow("textImage");
		run("Duplicate...", "title=label_mask");
		setThreshold(0, 128);
		setOption("BlackBackground", false);
		run("Convert to Mask");
		/*
		Create drop shadow if desired */
		if (shadowDrop!=0 || shadowDisp!=0)
			createShadowDropFromMask7Safe("label_mask", shadowDrop, shadowDisp, shadowBlur, shadowDarkness, outlineStroke);
		/* Apply drop shadow or glow */
		if (isOpen("shadow") && (shadowDarkness>0))
			imageCalculator("Subtract", workingImage, "shadow");
		if (isOpen("shadow") && (shadowDarkness<0))	/* Glow */
			imageCalculator("Add", workingImage, "shadow");
		run("Select None");
		/* Create outline around text */
		getSelectionFromMask("label_mask");
		getSelectionBounds(maskX, maskY, null, null);
		outlineStrokeOffset = maxOf(0, (outlineStroke/2)-1);
		setSelectionLocation(maskX + outlineStrokeOffset, maskY + outlineStrokeOffset); /* Offset selection to create shadow effect */
		run("Enlarge...", "enlarge=" + outlineStroke + " pixel");
		setBackgroundFromColorName(outlineColor);
		run("Clear", "slice");
		run("Enlarge...", "enlarge=" + outlineStrokeOffset + " pixel");
		run("Gaussian Blur...", "sigma=" + outlineStrokeOffset);
		run("Select None");
		/* Create text */
		getSelectionFromMask("label_mask");
		setBackgroundFromColorName(fontColor);
		run("Clear", "slice");
		run("Select None");
		/* Create inner shadow if requested */
		if (effect=="raised" || effect=="recessed"){ /* 'raised' and 'recessed' cannot be combined in this macro */
			fontLineWidth = getStringWidth("!");
			rAlpha = fontLineWidth/40;
			getSelectionFromMask("label_mask");
			if(outlineStroke>0) run("Enlarge...", "enlarge=1 pixel");
			run("Convolve...", "text1=[ " + createConvolverMatrix(effect, fontLineWidth) + " ]");
			if (rAlpha>0.33) run("Gaussian Blur...", "sigma=" + rAlpha);
			run("Select None");
		}
		/* The following steps smooth the interior of the text labels */
		selectWindow("textImage");
		getSelectionFromMask("label_mask");
		run("Make Inverse");
		run("Invert");
		run("Select None");
		imageCalculator("Min", workingImage, "textImage");
		closeImageByTitle("shadow");
		closeImageByTitle("inner_shadow");
		closeImageByTitle("label_mask");
	}
	function getDateTimeCode() {
		/* v211014 based on getDateCode v170823 */
		getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
		month = month + 1; /* Month starts at zero, presumably to be used in array */
		if(month<10) monthStr = "0" + month;
		else monthStr = "" + month;
		if (dayOfMonth<10) dayOfMonth = "0" + dayOfMonth;
		dateCodeUS = monthStr + dayOfMonth + substring(year, 2) + "-" + hour + "h" + minute + "m";
		return dateCodeUS;
	}
/*
	 Macro Color Functions
 */
	function getColorArrayFromColorName(colorName) {
		/* v180828 added Fluorescent Colors
		   v181017-8 added off-white and off-black for use in gif transparency and also added safe exit if no color match found
		   v191211 added Cyan
		   v211022 all names lower-case, all spaces to underscores v220225 Added more hash value comments as a reference v220706 restores missing magenta
		   v230130 Added more descriptions and modified order.
		   v230908: Returns "white" array if not match is found and logs issues without exiting.
		   v240123: Removed duplicate entries: Now 53 unique colors.
		   v240709: Added 2024 FSU-Branding Colors. Some reorganization. Now 60 unique colors.
		*/
		functionL = "getColorArrayFromColorName_v240709";
		cA = newArray(255, 255, 255); /* defaults to white */
		if (colorName == "white") cA = newArray(255, 255, 255);
		else if (colorName == "black") cA = newArray(0, 0, 0);
		else if (colorName == "off-white") cA = newArray(245, 245, 245);
		else if (colorName == "off-black") cA = newArray(10, 10, 10);
		else if (colorName == "light_gray") cA = newArray(200, 200, 200);
		else if (colorName == "gray") cA = newArray(127, 127, 127);
		else if (colorName == "dark_gray") cA = newArray(51, 51, 51);
		else if (colorName == "red") cA = newArray(255, 0, 0);
		else if (colorName == "green") cA = newArray(0, 255, 0);						/* #00FF00 AKA Lime green */
		else if (colorName == "blue") cA = newArray(0, 0, 255);
		else if (colorName == "cyan") cA = newArray(0, 255, 255);
		else if (colorName == "yellow") cA = newArray(255, 255, 0);
		else if (colorName == "magenta") cA = newArray(255, 0, 255);					/* #FF00FF */
		else if (colorName == "pink") cA = newArray(255, 192, 203);
		else if (colorName == "violet") cA = newArray(127, 0, 255);
		else if (colorName == "orange") cA = newArray(255, 165, 0);
			/* Excel Modern  + */
		else if (colorName == "aqua_modern") cA = newArray(75, 172, 198);			/* #4bacc6 AKA "Viking" aqua */
		else if (colorName == "blue_accent_modern") cA = newArray(79, 129, 189);	/* #4f81bd */
		else if (colorName == "blue_dark_modern") cA = newArray(31, 73, 125);		/* #1F497D */
		else if (colorName == "blue_honolulu") cA = newArray(0, 118, 182);			/* Honolulu Blue #006db0 */
		else if (colorName == "blue_modern") cA = newArray(58, 93, 174);			/* #3a5dae */
		else if (colorName == "gray_modern") cA = newArray(83, 86, 90);				/* bright gray #53565A */
		else if (colorName == "green_dark_modern") cA = newArray(121, 133, 65);		/* Wasabi #798541 */
		else if (colorName == "green_modern") cA = newArray(155, 187, 89);			/* #9bbb59 AKA "Chelsea Cucumber" */
		else if (colorName == "green_modern_accent") cA = newArray(214, 228, 187); 	/* #D6E4BB AKA "Gin" */
		else if (colorName == "green_spring_accent") cA = newArray(0, 255, 102);	/* #00FF66 AKA "Spring Green" */
		else if (colorName == "orange_modern") cA = newArray(247, 150, 70);			/* #f79646 tan hide, light orange */
		else if (colorName == "pink_modern") cA = newArray(255, 105, 180);			/* hot pink #ff69b4 */
		else if (colorName == "purple_modern") cA = newArray(128, 100, 162);		/* blue-magenta, purple paradise #8064A2 */
		else if (colorName == "red_n_modern") cA = newArray(227, 24, 55);
		else if (colorName == "red_modern") cA = newArray(192, 80, 77);
		else if (colorName == "tan_modern") cA = newArray(238, 236, 225);
		else if (colorName == "violet_modern") cA = newArray(76, 65, 132);
		else if (colorName == "yellow_modern") cA = newArray(247, 238, 69);
			/* FSU */
		else if (colorName == "garnet") cA = newArray(120, 47, 64);					/* #782F40 */
		else if (colorName == "gold") cA = newArray(206, 184, 136);					/* #CEB888 */
		else if (colorName == "gulf_sands") cA = newArray(223, 209, 167);				/* #DFD1A7 */
		else if (colorName == "stadium_night") cA = newArray(16, 24, 32);				/* #101820 */
		else if (colorName == "westcott_water") cA = newArray(92, 184, 178);			/* #5CB8B2 */
		else if (colorName == "vault_garnet") cA = newArray(166, 25, 46);				/* #A6192E */
		else if (colorName == "legacy_blue") cA = newArray(66, 85, 99);				/* #425563 */
		else if (colorName == "plaza_brick") cA = newArray(66, 85, 99);				/* #572932  */
		else if (colorName == "vault_gold") cA = newArray(255, 199, 44);				/* #FFC72C  */
		   /* Fluorescent Colors https://www.w3schools.com/colors/colors_crayola.asp   */
		else if (colorName == "radical_red") cA = newArray(255, 53, 94);			/* #FF355E */
		else if (colorName == "jazzberry_jam") cA = newArray(165, 11, 94);
		else if (colorName == "wild_watermelon") cA = newArray(253, 91, 120);		/* #FD5B78 */
		else if (colorName == "shocking_pink") cA = newArray(255, 110, 255);		/* #FF6EFF Ultra Pink */
		else if (colorName == "razzle_dazzle_rose") cA = newArray(238, 52, 210);	/* #EE34D2 */
		else if (colorName == "hot_magenta") cA = newArray(255, 0, 204);			/* #FF00CC AKA Purple Pizzazz */
		else if (colorName == "outrageous_orange") cA = newArray(255, 96, 55);		/* #FF6037 */
		else if (colorName == "supernova_orange") cA = newArray(255, 191, 63);		/* FFBF3F Supernova Neon Orange*/
		else if (colorName == "sunglow") cA = newArray(255, 204, 51);				/* #FFCC33 */
		else if (colorName == "neon_carrot") cA = newArray(255, 153, 51);			/* #FF9933 */
		else if (colorName == "atomic_tangerine") cA = newArray(255, 153, 102);		/* #FF9966 */
		else if (colorName == "laser_lemon") cA = newArray(255, 255, 102);			/* #FFFF66 "Unmellow Yellow" */
		else if (colorName == "electric_lime") cA = newArray(204, 255, 0);			/* #CCFF00 */
		else if (colorName == "screamin'_green") cA = newArray(102, 255, 102);		/* #66FF66 */
		else if (colorName == "magic_mint") cA = newArray(170, 240, 209);			/* #AAF0D1 */
		else if (colorName == "blizzard_blue") cA = newArray(80, 191, 230);		/* #50BFE6 Malibu */
		else if (colorName == "dodger_blue") cA = newArray(9, 159, 255);			/* #099FFF Dodger Neon Blue */
		else IJ.log(colorName + " not found in " + functionL + ": Color defaulted to white");
		return cA;
	}
	function setBackgroundFromColorName(colorName) {
		colorArray = getColorArrayFromColorName(colorName);
		setBackgroundColor(colorArray[0], colorArray[1], colorArray[2]);
	}
	function setColorFromColorName(colorName) {
		colorArray = getColorArrayFromColorName(colorName);
		setColor(colorArray[0], colorArray[1], colorArray[2]);
	}
	function setForegroundColorFromName(colorName) {
		colorArray = getColorArrayFromColorName(colorName);
		setForegroundColor(colorArray[0], colorArray[1], colorArray[2]);
	}
	/* Hex conversion below adapted from T.Ferreira, 20010.01 https://imagej.net/doku.php?id=macro:rgbtohex */
	function getHexColorFromColorName(colorNameString) {
		/* v231207: Uses IJ String.pad instead of function: pad */
		colorArray = getColorArrayFromColorName(colorNameString);
		 r = toHex(colorArray[0]); g = toHex(colorArray[1]); b = toHex(colorArray[2]);
		 hexName= "#" + "" + String.pad(r, 2) + "" + String.pad(g, 2) + "" + String.pad(b, 2);
		 return hexName;
	}	
	function getLutsList() {
		/* v180723 added check for preferred LUTs
			v210430 expandable array version    v211029 added cividis.lut to LUT favorites v220113 added cividis-asc-linearlumin
		*/
		defaultLuts= getList("LUTs");
		Array.sort(defaultLuts);
		lutsDir = getDirectory("LUTs");
		/* A list of frequently used LUTs for the top of the menu list . . . */
		preferredLutsList = newArray("Your favorite LUTS here", "cividis-asc-linearlumin", "cividis", "viridis-linearlumin", "silver-asc", "mpl-viridis", "mpl-plasma", "Glasbey", "Grays");
		preferredLuts = newArray;
		/* Filter preferredLutsList to make sure they are available . . . */
		for (i=0, countL=0; i<preferredLutsList.length; i++) {
			for (j=0; j<defaultLuts.length; j++) {
				if (preferredLutsList[i] == defaultLuts[j]) {
					preferredLuts[countL] = preferredLutsList[i];
					countL++;
					j = defaultLuts.length;
				}
			}
		}
		lutsList=Array.concat(preferredLuts, defaultLuts);
		return lutsList; /* Required to return new array */
	}
	function hexLutColors() {
		/* v231207: Uses String.pad instead of function: pad */
		getLut(reds, greens, blues);
		hexColors= newArray(256);
		for (i=0; i<256; i++) {
			r= toHex(reds[i]); g= toHex(greens[i]); b= toHex(blues[i]);
			hexColors[i]= "" + String.pad(r, 2) + "" + String.pad(g, 2) + "" + String.pad(b, 2);
		}
		return hexColors;
	}
	/*
	End of ASC-mod BAR Color Functions
	*/
  	function getFontChoiceList() {
		/*	v180723 first version
			v180828 Changed order of favorites. v190108 Longer list of favorites. v230209 Minor optimization.
			v230919 You can add a list of fonts that do not produce good results with the macro. 230921 more exclusions.
		*/
		systemFonts = getFontList();
		IJFonts = newArray("SansSerif", "Serif", "Monospaced");
		fontNameChoices = Array.concat(IJFonts, systemFonts);
		blackFonts = Array.filter(fontNameChoices, "([A-Za-z] + .*[bB]l.*k)");
		eBFonts = Array.filter(fontNameChoices, "([A-Za-z] + .*[Ee]xtra.*[Bb]old)");
		uBFonts = Array.filter(fontNameChoices, "([A-Za-z] + .*[Uu]ltra.*[Bb]old)");
		fontNameChoices = Array.concat(blackFonts, eBFonts, uBFonts, fontNameChoices); /* 'Black' and Extra and Extra Bold fonts work best */
		faveFontList = newArray("Your favorite fonts here", "Arial Black", "Myriad Pro Black", "Myriad Pro Black Cond", "Noto Sans Blk", "Noto Sans Disp Cond Blk", "Open Sans ExtraBold", "Roboto Black", "Alegreya Black", "Alegreya Sans Black", "Tahoma Bold", "Calibri Bold", "Helvetica", "SansSerif", "Calibri", "Roboto", "Tahoma", "Times New Roman Bold", "Times Bold", "Goldman Sans Black", "Goldman Sans", "Serif");
		/* Some fonts or font families don't work well with ASC macros, typically they do not support all useful symbols, they can be excluded here using the .* regular expression */
		offFontList = newArray("Alegreya SC Black", "Archivo.*", "Arial Rounded.*", "Bodon.*", "Cooper.*", "Eras.*", "Fira.*", "Gill Sans.*", "Lato.*", "Libre.*", "Lucida.*", "Merriweather.*", "Montserrat.*", "Nunito.*", "Olympia.*", "Poppins.*", "Rockwell.*", "Tw Cen.*", "Wingdings.*", "ZWAdobe.*"); /* These don't work so well. Use a ".*" to remove families */
		faveFontListCheck = newArray(faveFontList.length);
		for (i=0, counter=0; i<faveFontList.length; i++) {
			for (j=0; j<fontNameChoices.length; j++) {
				if (faveFontList[i] == fontNameChoices[j]) {
					faveFontListCheck[counter] = faveFontList[i];
					j = fontNameChoices.length;
					counter++;
				}
			}
		}
		faveFontListCheck = Array.trim(faveFontListCheck, counter);
		for (i=0; i<fontNameChoices.length; i++) {
			for (j=0; j<offFontList.length; j++){
				if (fontNameChoices[i]==offFontList[j]) fontNameChoices = Array.deleteIndex(fontNameChoices, i);
				if (endsWith(offFontList[j], ".*")){
					if (startsWith(fontNameChoices[i], substring(offFontList[j], 0, indexOf(offFontList[j], ".*")))){
						fontNameChoices = Array.deleteIndex(fontNameChoices, i);
						i = maxOf(0, i-1); 
					} 
					// fontNameChoices = Array.filter(fontNameChoices, "(^" + offFontList[j] + ")"); /* RegEx not working and very slow */
				} 
			} 
		}
		fontNameChoices = Array.concat(faveFontListCheck, fontNameChoices);
		for (i=0; i<fontNameChoices.length; i++) {
			for (j=i + 1; j<fontNameChoices.length; j++)
				if (fontNameChoices[i]==fontNameChoices[j]) fontNameChoices = Array.deleteIndex(fontNameChoices, j);
		}
		return fontNameChoices;
	}
	function getSelectionFromMask(sel_M){
		/* v220920 only inverts if full image selection */
		batchMode = is("Batch Mode"); /* Store batch status mode before toggling */
		if (!batchMode) setBatchMode(true); /* Toggle batch mode on if previously off */
		tempID = getImageID();
		selectWindow(sel_M);
		run("Create Selection"); /* Selection inverted perhaps because the mask has an inverted LUT? */
		getSelectionBounds(gSelX, gSelY, gWidth, gHeight);
		if(gSelX==0 && gSelY==0 && gWidth==Image.width && gHeight==Image.height)	run("Make Inverse");
		run("Select None");
		selectImage(tempID);
		run("Restore Selection");
		if (!batchMode) setBatchMode(false); /* Return to original batch mode setting */
	}
	function guessBGMedianIntensity(){
		/* v220822: 1st color array version (based on https://wsr.imagej.net//macros/tools/ColorPickerTool.txt)
			v230728: Uses selected area if there is a non-line selection.
		*/
		if (selectionType<0 || selectionType>4){
			sW = Image.width-1;
			sH = Image.height-1;
			sX = 0;
			sY = 0;
		}
		else {
			getSelectionBounds(sX, sY, sW, sH);
			sW += sX;
			sH += sY;
		}
		interrogate = round(maxOf(1, (sW + sH)/200));
		if (bitDepth==24){red = 0; green = 0; blue = 0;}
		else int = 0;
		xC = newArray(sX, sW, sX, sW);
		yC = newArray(sY, sY, sH, sH);
		xAdd = newArray(1, -1, 1, -1);
		yAdd = newArray(1, 1, -1, -1);
		if (bitDepth==24){ reds = newArray(); greens = newArray(); blues = newArray();}
		else ints = newArray;
		for (i=0; i<xC.length; i++){
			for(j=0;j<interrogate;j++){
				if (bitDepth==24){
					v = getPixel(xC[i] + j*xAdd[i], yC[i] + j*yAdd[i]);
					reds = Array.concat(reds, (v>>16)&0xff);  /* extract red byte (bits 23-17) */
	           		greens = Array.concat(greens, (v>>8)&0xff); /* extract green byte (bits 15-8) */
	            	blues = Array.concat(blues, v&0xff);       /* extract blue byte (bits 7-0) */
				}
				else ints = Array.concat(ints, getValue(xC[i] + j*xAdd[i], yC[i] + j*yAdd[i]));
			}
		}
		midV = round((xC.length-1)/2);
		if (bitDepth==24){
			reds = Array.sort(reds); greens = Array.sort(greens); blues = Array.sort(blues);
			medianVals = newArray(reds[midV], greens[midV], blues[midV]);
		}
		else{
			ints = Array.sort(ints);
			medianVals = newArray(ints[midV], ints[midV], ints[midV]);
		}
		return medianVals;
	}
	function indexOfArray(array, value, default) {
		/* v190423 Adds "default" parameter (use -1 for backwards compatibility). Returns only first found value
			v230902 Limits default value to array size */
		index = minOf(lengthOf(array) - 1, default);
		for (i=0; i<lengthOf(array); i++){
			if (array[i]==value) {
				index = i;
				i = lengthOf(array);
			}
		}
	  return index;
	}
	function indexOfArrayThatStartsWith(array, value, default) {
		/* Like indexOfArray but partial matches possible
			v220804 1st version
			v230902 Limits default value to array size */
		indexFound = minOf(lengthOf(array) - 1, default);
		for (i=0; i<lengthOf(array); i++){
			if (indexOf(array[i], value)==0){
				indexFound = i;
				i = lengthOf(array);
			}
		}
		return indexFound;
	}
	function lnArray(arrayName) {
	/* 1st version: v180318 */
		outputArray = Array.copy(arrayName);
		for (i=0; i<lengthOf(arrayName); i++)
			outputArray[i] = log(arrayName[i]);
		return outputArray;
	}
	function memFlush(waitTime) {
		run("Reset...", "reset=[Undo Buffer]");
		wait(waitTime);
		run("Reset...", "reset=[Locked Image]");
		wait(waitTime);
		call("java.lang.System.gc"); /* force a garbage collection */
		wait(waitTime);
	}
	function rangeFinder(dataExtreme, max){
	/*	For finding good end values for ramps and plot ranges.
		v230824: 1st version  Peter J. Lee Applied Superconductivity Center FSU */
		rangeExtremeStr = d2s(dataExtreme, -2);
		if (max) rangeExtremeA = Math.ceil(10 * parseFloat(substring(rangeExtremeStr, 0, indexOf(rangeExtremeStr, "E")))) / 10;
		else rangeExtremeA = Math.floor(10 * parseFloat(substring(rangeExtremeStr, 0, indexOf(rangeExtremeStr, "E")))) / 10;
		rangeExtremeStrB = substring(rangeExtremeStr, indexOf(rangeExtremeStr, "E") + 1);
		rangeExtreme = parseFloat(rangeExtremeA + "E" + rangeExtremeStrB);
		return rangeExtreme;
	}
	function removeBlackEdgeObjects(){
	/*	Remove black edge objects without using Analyze Particles
	Peter J. Lee  National High Magnetic Field Laboratory
	1st version v190604
	v200102 Removed unnecessary print command.
	v230106 Does not require any plugins or other functions, uses Functions for working with colors available in ImageJ 1.53h and later
	*/
		requires("1.53h");	
		originalFGCol = Color.foreground;
		Color.setForeground("white");
		cWidth = getWidth() + 2; cHeight = getHeight() + 2;
		run("Canvas Size...", "width=" + cWidth + " height=" + cHeight + " position=Center zero");
		floodFill(0, 0);
		makeRectangle(1, 1, cWidth-2, cHeight-2);
		run("Crop");
		showStatus("Remove_Edge_Objects function complete");
		Color.setForeground(originalFGCol);
	}
	function removeDuplicatesInArray(array, sortFlag) {
		/* v230822-3: 1st version.  Peter J. Lee FSU	*/
		if (lengthOf(array)<=1) return array;
		else {
			if (!sortFlag) arrayOrder = Array.rankPositions(array);
			sortedArray = Array.sort(array);
			for (i=0; i<lengthOf(sortedArray)-1; i++){
				if (sortedArray[i]==sortedArray[i + 1]){
					sortedArray = Array.deleteIndex(sortedArray, i);
					if (!sortFlag) arrayOrder = Array.deleteIndex(arrayOrder, i);
					i -= 1;
				}
			}
			if (!sortFlag) Array.sort(arrayOrder, sortedArray);
			return sortedArray;
		}
	}
	function removeTrailingZerosAndPeriod(string) {
	/* Removes any trailing zeros after a period
	v210430 totally new version: Note: Requires remTZeroP function
	Nested string functions require "" prefix
	*/
		lIP = lastIndexOf(string, ".");
		if (lIP>=0) {
			lIP = lengthOf(string) - lIP;
			string = "" + remTZeroP(string, lIP);
		}
		return string;
	}
	function remTZeroP(string, iterations){
		for (i=0; i<iterations; i++){
			if (endsWith(string, "0"))
				string = substring(string, 0, lengthOf(string)-1);
			else if (endsWith(string, "."))
				string = substring(string, 0, lengthOf(string)-1);
			/* Must be "else if" because we only want one removal per iteration */
		}
		return string;
	}
	function restoreExit(message){ /* Make a clean exit from a macro, restoring previous settings */
		/* v200305 first version using memFlush function
			v220316 if message is blank this should still work now
			REQUIRES saveSettings AND memFlush
		*/
		restoreSettings(); /* Restore previous settings before exiting */
		setBatchMode("exit & display"); /* Probably not necessary if exiting gracefully but otherwise harmless */
		memFlush(200);
		if (message!="") exit(message);
		else exit;
	}
	function runDemo() { /* Generates standard imageJ demo blob analysis */
	/* v180104 */
	    run("Blobs (25K)");
		run("Auto Threshold", "method=Default");
		run("Convert to Mask");
		run("Set Scale...", "distance=10 known=1 unit=um"); /* Add an arbitrary scale to demonstrate unit usage. */
		run("Analyze Particles...", "display exclude clear add");
		resetThreshold();
		if(is("Inverting LUT")) run("Invert LUT");
	}
	function stripKnownExtensionFromString(string) {
		/*	Note: Do not use on path as it may change the directory names
		v210924: Tries to make sure string stays as string.	v211014: Adds some additional cleanup.	v211025: fixes multiple 'known's issue.	v211101: Added ".Ext_" removal.
		v211104: Restricts cleanup to end of string to reduce risk of corrupting path.	v211112: Tries to fix trapped extension before channel listing. Adds xlsx extension.
		v220615: Tries to fix the fix for the trapped extensions ...	v230504: Protects directory path if included in string. Only removes doubled spaces and lines.
		v230505: Unwanted dupes replaced by unusefulCombos.	v230607: Quick fix for infinite loop on one of while statements.
		v230614: Added AVI.	v230905: Better fix for infinite loop. v230914: Added BMP and "_transp" and rearranged
		*/
		fS = File.separator;
		string = "" + string;
		protectedPathEnd = lastIndexOf(string, fS) + 1;
		if (protectedPathEnd>0){
			protectedPath = substring(string, 0, protectedPathEnd);
			string = substring(string, protectedPathEnd);
		}
		unusefulCombos = newArray("-", "_", " ");
		for (i=0; i<lengthOf(unusefulCombos); i++){
			for (j=0; j<lengthOf(unusefulCombos); j++){
				combo = unusefulCombos[i] + unusefulCombos[j];
				while (indexOf(string, combo)>=0) string = replace(string, combo, unusefulCombos[i]);
			}
		}
		if (lastIndexOf(string, ".")>0 || lastIndexOf(string, "_lzw")>0) {
			knownExts = newArray(".avi", ".csv", ".bmp", ".dsx", ".gif", ".jpg", ".jpeg", ".jp2", ".png", ".tif", ".txt", ".xlsx");
			knownExts = Array.concat(knownExts, knownExts, "_transp", "_lzw");
			kEL = knownExts.length;
			for (i=0; i<kEL/2; i++) knownExts[i] = toUpperCase(knownExts[i]);
			chanLabels = newArray(" \(red\)", " \(green\)", " \(blue\)", "\(red\)", "\(green\)", "\(blue\)");
			for (i=0, k=0; i<kEL; i++) {
				for (j=0; j<chanLabels.length; j++){ /* Looking for channel-label-trapped extensions */
					iChanLabels = lastIndexOf(string, chanLabels[j])-1;
					if (iChanLabels>0){
						preChan = substring(string, 0, iChanLabels);
						postChan = substring(string, iChanLabels);
						while (indexOf(preChan, knownExts[i])>0){
							preChan = replace(preChan, knownExts[i], "");
							string =  preChan + postChan;
						}
					}
				}
				while (endsWith(string, knownExts[i])) string = "" + substring(string, 0, lastIndexOf(string, knownExts[i]));
			}
		}
		unwantedSuffixes = newArray(" ", "_", "-");
		for (i=0; i<unwantedSuffixes.length; i++){
			while (endsWith(string, unwantedSuffixes[i])) string = substring(string, 0, string.length-lengthOf(unwantedSuffixes[i])); /* cleanup previous suffix */
		}
		if (protectedPathEnd>0){
			if(!endsWith(protectedPath, fS)) protectedPath += fS;
			string = protectedPath + string;
		}
		return string;
	}
	function stripUnitFromString(string) {
		if (endsWith(string, "\)")) { /* Label with units from string if enclosed by parentheses */
			unitIndexStart = lastIndexOf(string, "\(");
			unitIndexEnd = lastIndexOf(string, "\)");
			stringUnit = substring(string, unitIndexStart + 1, unitIndexEnd);
			unitCheck = matches(stringUnit, ".*[0-9].*");
			if (unitCheck==0) {  /* If the "unit" contains a number it probably isn't a unit */
				stringLabel = substring(string, 0, unitIndexStart);
			}
			else stringLabel = string;
		}
		else stringLabel = string;
		return stringLabel;
	}
	function toWhiteBGBinary(windowTitle) { /* For black objects on a white background */
		/* Replaces binaryCheck function
		v220707
		v? 	Warns but does not exit.
		*/
		selectWindow(windowTitle);
		if (!is("binary")) run("8-bit");
		/* Quick-n-dirty threshold if not previously thresholded */
		getThreshold(t1, t2);
		if (t1==-1)  {
			run("8-bit");
			run("Auto Threshold", "method=Default");
			setOption("BlackBackground", false);
			run("Make Binary");
		}
		if (is("Inverting LUT")) run("Invert LUT");
		/* Make sure black objects on white background for consistency */
		yMax = Image.height-1;	xMax = Image.width-1;
		cornerPixels = newArray(getPixel(0, 0), getPixel(1, 1), getPixel(0, yMax), getPixel(xMax, 0), getPixel(xMax, yMax), getPixel(xMax-1, yMax-1));
		Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
		if (cornerMax!=cornerMin) IJ.log("Warning: There may be a problem with the image border, there are different pixel intensities at the corners");
		/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
			i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
		if (cornerMean<1) run("Invert");
	}
	function unCleanLabel(string) {
	/* v161104 This function replaces special characters with standard characters for file system compatible filenames.
	+ 041117b to remove spaces as well.
	+ v220126 added getInfo("micrometer.abbreviation").
	+ v220128 add loops that allow removal of multiple duplication.
	+ v220131 fixed so that suffix cleanup works even if extensions are included.
	+ v220616 Minor index range fix that does not seem to have an impact if macro is working as planned. v220715 added 8-bit to unwanted dupes. v220812 minor changes to micron and Ångström handling
	+ v231005 Replaced superscript abbreviations that did not work.
	+ v240124 Replace _+_ with +.
	*/
		/* Remove bad characters */
		string = string.replace(fromCharCode(178), "sup2"); /* superscript 2 */
		string = string.replace(fromCharCode(179), "sup3"); /* superscript 3 UTF-16 (decimal) */
		string = string.replace(fromCharCode(0xFE63) + fromCharCode(185), "sup-1"); /* Small hyphen substituted for superscript minus as 0x207B does not display in table */
		string = string.replace(fromCharCode(0xFE63) + fromCharCode(178), "sup-2"); /* Small hyphen substituted for superscript minus as 0x207B does not display in table */
		string = string.replace(fromCharCode(181) + "m", "um"); /* micron units */
		string = string.replace(getInfo("micrometer.abbreviation"), "um"); /* micron units */
		string = string.replace(fromCharCode(197), "Angstrom"); /* Ångström unit symbol */
		string = string.replace(fromCharCode(0x212B), "Angstrom"); /* the other Ångström unit symbol */
		string = string.replace(fromCharCode(0x2009) + fromCharCode(0x00B0), "deg"); /* replace thin spaces degrees combination */
		string = string.replace(fromCharCode(0x2009), "_"); /* Replace thin spaces  */
		string = string.replace("%", "pc"); /* % causes issues with html listing */
		string = string.replace(" ", "_"); /* Replace spaces - these can be a problem with image combination */
		/* Remove duplicate strings */
		unwantedDupes = newArray("8bit", "8-bit", "lzw");
		for (i=0; i<lengthOf(unwantedDupes); i++){
			iLast = lastIndexOf(string, unwantedDupes[i]);
			iFirst = indexOf(string, unwantedDupes[i]);
			if (iFirst!=iLast) {
				string = string.substring(0, iFirst) + string.substring(iFirst + lengthOf(unwantedDupes[i]));
				i = -1; /* check again */
			}
		}
		unwantedDbls = newArray("_-", "-_", "__", "--", "\\+\\+");
		for (i=0; i<lengthOf(unwantedDbls); i++){
			iFirst = indexOf(string, unwantedDbls[i]);
			if (iFirst>=0) {
				string = string.substring(0, iFirst) + string.substring(string, iFirst + lengthOf(unwantedDbls[i]) / 2);
				i = -1; /* check again */
			}
		}
		string = string.replace("_\\+", "\\+"); /* Clean up autofilenames */
		string = string.replace("\\+_", "\\+"); /* Clean up autofilenames */
		/* cleanup suffixes */
		unwantedSuffixes = newArray(" ", "_", "-", "\\+"); /* things you don't wasn't to end a filename with */
		extStart = lastIndexOf(string, ".");
		sL = lengthOf(string);
		if (sL-extStart<=4 && extStart>0) extIncl = true;
		else extIncl = false;
		if (extIncl){
			preString = substring(string, 0, extStart);
			extString = substring(string, extStart);
		}
		else {
			preString = string;
			extString = "";
		}
		for (i=0; i<lengthOf(unwantedSuffixes); i++){
			sL = lengthOf(preString);
			if (endsWith(preString, unwantedSuffixes[i])) {
				preString = substring(preString, 0, sL-lengthOf(unwantedSuffixes[i])); /* cleanup previous suffix */
				i=-1; /* check one more time */
			}
		}
		if (!endsWith(preString, "_lzw") && !endsWith(preString, "_lzw.")) preString = replace(preString, "_lzw", ""); /* Only want to keep this if it is at the end */
		string = preString + extString;
		/* End of suffix cleanup */
		return string;
	}
	function unitLabelFromString(string, imageUnit) {
	/* v180404 added Feret_MinDAngle_Offset
		v210823 REQUIRES ASC function indexOfArray(array, string, default) for expanded "unitless" array.
		v220808 Replaces ° with fromCharCode(0x00B0).
		v230109 Expand px to pixels. Simplify angleUnits.
		v231005 Look and underscores replaced by spaces too.
		*/
		if (endsWith(string, "\)")) { /* Label with units from string if enclosed by parentheses */
			unitIndexStart = lastIndexOf(string, "\(");
			unitIndexEnd = lastIndexOf(string, "\)");
			stringUnit = substring(string, unitIndexStart + 1, unitIndexEnd);
			unitCheck = matches(stringUnit, ".*[0-9].*");
			if (unitCheck==0) {  /* If the "unit" contains a number it probably isn't a unit unless it is the 0-90 degress setting */
				unitLabel = stringUnit;
			}
			else if (indexOf(stringUnit, "0-90")<0 || indexOf(stringUnit, "0to90")<0) unitLabel = fromCharCode(0x00B0);
			else {
				unitLabel = "";
			}
		}
		else {
			noUnits = newArray("Circ.", "Slice", "AR", "Round", "Solidity", "Image_Name", "PixelAR", "ROI_name", "ObjectN", "AR_Box", "AR_Feret", "Rnd_Feret", "Compact_Feret", "Elongation", "Thinnes_Ratio", "Squarity_AP", "Squarity_AF", "Squarity_Ff", "Convexity", "Rndnss_cAR", "Fbr_Snk_Crl", "Fbr_Rss2_Crl", "AR_Fbr_Snk", "Extent", "HSF", "HSFR", "Hexagonality");
			noUnitSs = newArray;
			for (i=0; i<noUnits.length; i++) noUnitSs[i] = replace(noUnits[i], "_", " ");
			angleUnits = newArray("Angle", "FeretAngle", "Cir_to_El_Tilt", "0-90", fromCharCode(0x00B0), "0to90", "degrees");
			angleUnitSs = newArray;
			for (i=0 ; i<angleUnits.length; i++) angleUnitSs[i] = replace(angleUnits[i], "_", " ");
			chooseUnits = newArray("Mean" , "StdDev" , "Mode" , "Min" , "Max" , "IntDen" , "Median" , "RawIntDen" , "Slice");
			if (string=="Area") unitLabel = imageUnit + fromCharCode(178);
			else if (indexOfArray(noUnits, string, -1)>=0) unitLabel = "None";
			else if (indexOfArray(noUnitSs, string, -1)>=0) unitLabel = "None";
			else if (indexOfArray(chooseUnits, string, -1)>=0) unitLabel = "";
			else if (indexOfArray(angleUnits, string, -1)>=0) unitLabel = fromCharCode(0x00B0);
			else if (indexOfArray(angleUnitSs, string, -1)>=0) unitLabel = fromCharCode(0x00B0);
			else if (string=="%Area") unitLabel = "%";
			else unitLabel = imageUnit;
			if (indexOf(unitLabel, "px")>=0) unitLabel = "pixels";
		}
		return unitLabel;
	}
	/* History:
	 + Peter J. Lee mods 6/16/16-6/30/2016 to automate defaults and add labels to ROIs
	 + add scaled labels 7/7/2016
	 + add ability to reverse LUT and also shows min and max values for all measurements to make it easier to choose a range 8/5/2016
 	 + min and max lines for ramp
	 + added option to make a new combined image that combines the labeled image with the legend 10/1/2016
	 + added the ability to add lines on ramp for statistics
 	 + min and max lines for ramp
	 + added option to make a new combined image that combines the labeled image with the legend 10/1/2016
	 + added the ability to add lines on ramp for statistics
	Adjusted to allow Grays-only if selected and default to white background.
	 + adds choice for number of lines of statistics (not really needed)
	 + v161117 adds more decimal place control
	 + v170914 Added garbage clean up as suggested by Luc LaLonde at LBNL.
	 + v171024 Added an option to just label the objects without color coding
	 + v171114 Added screen height sensitive menus (also tweaked for less bloat in v171117).
	 + v171117 Ramp improvements: Added minor tick labels, changed label spacing to "intervals", corrected label locations.
	 + v180104 Updated functions to latest versions.
	 + v180105 Restrict labels to within frame and fixed issue with very small font sizes.
	 + v180108 Fixed shadow/function mismatch that produced poor shading of text.
	 + v180215 Replaces all instances of array.length with lengthOf function to workaround bug in ImageJ 1.51u.
	 + v180228 Ramp: Improved text quality for statistics labels and improved tick marks.
	 + v180302 Unitless comma removed from ramp label.
	 + v180315 Reordered 1st menu.
	 + v180319 Added log stats output options, increased sigma option up to 4sigma and further refined initial dialog
	 + v180323 Further tweaks to the histogram appearance and a fix for instances where the mode is in the 1st bin.
	 + v180323b Adds options to crop image before combining with ramp. Also add options to skip adding labels.
	 + v180326 Restored missing frequency distribution column.
	 + v180329 Changed line width for frequency plot to work better for very large images.
	 + v180403 Changed min-max and SD label limits to prevent overlap of SD and min-max labels (min-max labels take priority).
	 + v180404 Fixed above. 	 + v180601 Adds choice to invert and choice of images. + v180602 Added MC-Centroid 0.5 pixel offset.
	 + v180716 Fixed unnecessary bailout for small distributions that do not produce an interquartile range.
	 + v180717 More fixes for small distributions that do not produce an interquartile range.
	 + v180718 Reorganized ramp options to make ramp labels easy to edit.
	 + v180719 Added margin to auto-crop.
	 + v180722 Allows any system font to be used. Fixed selected positions.
	 + v180810 Set minimum label font size to 10 as anything less is not very useful.
	 + v180831 Added check for Fiji_Plugins and corrected missing "pixel" argument in final margin enlargement.
	 + v180926 Added coded range option.
	 + v180928 Fixed 2 lines of missing code.
	 + v181003 Restored autocrop, updated functions.
	 + v190328 Fixed font color selection for non-standard colors. Tweaked ramp text alignment.
	 + v190509-10 Minor cleanup
	 + v190628 Add options to import ROI sets and Results table if either are empty or there is a count mismatch.
	 + v190701 Tweaked ramp height, removed duplicate color array, changed label alignment.
	 + v190731 Fixed modalBin error exception. Fixed issue with ROI coloring loop not advancing as expected in some conditions.
	 + v200305 Added shorter dialogs for lower resolution screens and added memory flushing function.
	 + v200604 Removed troublesome macro-path determination
	 + v200706 Changed imageDepth variable name.
	 + v210415 bug fix in 2nd dialog
	 + v210416-9 Improved menu options and various bug fixes. Updated ASC functions to latest versions.
	 + v210420-2 Replaced non-working coded range with LUT range option. v210422 bug fixes.
	 + v210429-v210503 Expandable arrays. Better ramp label optimization. Fixed image combination issue. Added auto-trimming of object labels option, corrected number of minor ticks
	 + v210823-5 Optional expansions of parameter labels to be more informative.
	 + v211022 All colors lower-case, restored cyan.
	 + v211025 Updated functions
	 + v211029 Fixed missing comment close below. Added cividis.lut to favorite luts
	 + v211104: Updated stripKnownExtensionFromString function    v211112: Again
	 + v211119: Added option to perform to create a Max calculated version to restore holes (not fully tested yet in all circumstances).
	 + v220701: Updates functions.
	 + v220706: Does not require binary image. f1: updated colors and v220707 replaced binary[-]Check with toWhiteBGBinary so it is more explicit.
	 + v220708: Reorganized menus to allow for more lines of statistics. f1-2: Updated color functions.
	 + v221209: fixed ln stats array length error.
	 + v230109: Improvements to parameter label expansion.
	*/