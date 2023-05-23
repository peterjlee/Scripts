/*	Fork of ROI_Color_Coder.ijm IJ BAR: https://github.com/tferr/Scripts#scripts
	https://imagej.net/doku.php?id=macro:roi_color_coder
	Colorizes ROIs by matching LUT indexes to measurements in the Results table.
	Based on the original by Tiago Ferreira, v.5.4 2017.03.10
	Peter J. Lee Applied Superconductivity Center, NHMFL
	Full history at the bottom of the file.
	v230414b-v230420: Formatting simplified, "raised" and "recessed" replace inner shadow, major preferences added.
	f1: updates stripKnownExtensionFromString function.
	v230517: Add summary save to text file option. v230517b: Keeps focus in selected image for coloring. Fixes saved settings for summary output.
	v230518: Fixed for missing ramp issue caused by spaces in image title. Reorganized unit choices.
	v230523: Cropped combination functionality restored.
 */
macro "ROI Color Coder with Scaled Labels and Summary" {
	macroL = "BAR_ROI_Color_Coder_Unit-Scaled_Labels_Summary_ASC_v230523.ijm";
	requires("1.53g"); /* Uses expandable arrays */
	close("*Ramp"); /* cleanup: closes previous ramp windows */
	call("java.lang.System.gc");
	if (!checkForPluginNameContains("Fiji_Plugins")) exit("Sorry this macro requires some functions in the Fiji_Plugins package");
	/* Needs Fiji_plugins for autoCrop */
	saveSettings;
	imageN = nImages;
	if (imageN==0){
		showMessageWithCancel("No images open or the ROI Manager is empty...\n"
        + "Run demo? (Results Table and ROI Manager will be cleared)");
	    runDemo();
	}
	orID = getImageID(); /* get id of image and title */
	t = getTitle();
	tPath = getDir("image");
	/* Check to see if there is a rectangular location already set for the summary */
	if (selectionType()==0) {
		getSelectionBounds(selPosStartX, selPosStartY, originalSelEWidth, originalSelEHeight);
		selectionExists = true;
	} else selectionExists = false;
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
	if (oImageDepth!=24){
		yMax = Image.height-1;	xMax = Image.width-1;
		cornerPixels = newArray(getPixel(0,0),getPixel(1,1),getPixel(0,yMax),getPixel(xMax,0),getPixel(xMax,yMax),getPixel(xMax-1,yMax-1));
		Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
		if (cornerMax!=cornerMin){
			actionOptions = newArray("Remove black edge objects","Invert, then remove black edge objects","Exit","Feeling lucky");
			Dialog.create("Border pixel inconsistency");
				Dialog.addMessage("cornerMax="+cornerMax+ " but cornerMin=" +cornerMin+ " and cornerMean = "+cornerMean+" problem with image border");
				Dialog.addRadioButtonGroup("Actions:",actionOptions,actionOptions.length,1,"Remove black edge objects");
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
	bgI = round((medianBGIs[0]+medianBGIs[1]+medianBGIs[2])/3);
	lcf = (pixelWidth+pixelHeight)/2; /* length conversion factor needed for morph. centroids */
	nRes = nResults;
	tSize = Table.size;
	if (nRes==0 && tSize>0){
		oTableTitle = Table.title;
		renameTable = getBoolean("There is no Results table but " + oTableTitle + "has " +tSize+ "rows:", "Rename to Results", "No, I will take may chances");
		if (renameTable) {
			Table.rename(oTableTitle, "Results");
			nRes = nResults;
		}
	}
	countNaN = 0; /* Set this counter here so it is not skipped by later decisions */
	menuLimit = 0.8 * screenHeight; /* used to limit menu size for small screens */
	// menuLimit = 700; /* for testing only resolution options only */
	numIntervals = 10; /* default number of ramp label intervals */
	sup2 = fromCharCode(178);
	degreeChar = fromCharCode(0x00B0);
	ums = getInfo("micrometer.abbreviation");
	outlineStrokePC = 6; /* default outline stroke: % of font size */
	if (nRes!=nROIs) restoreExit("Exit: Results table \(" + nRes + "\) and ROI Manager \(" + nROIs + "\) mismatch."); /* exit so that this ambiguity can be cleared up */
	if (nROIs<=1) restoreExit("Exit: ROI Manager has only \(" + nROIs + "\) entries."); /* exit so that this ambiguity can be cleared up */
	items = nROIs;
	run("Remove Overlay");
	setBatchMode(true);
	tN = stripKnownExtensionFromString(unCleanLabel(t)); /* File.nameWithoutExtension is specific to last opened file, also remove special characters that might cause issues saving file */
	if (lengthOf(tN)>43) tNL = substring(tN,0,21) + "..." + substring(tN, lengthOf(tN)-21);
	else tNL = tN;
	imageHeight = getHeight(); imageWidth = getWidth();
	rampH = round(0.89 * imageHeight); /* suggest ramp slightly small to allow room for labels */
	acceptMinFontSize = true;
	fontSize = maxOf(10,imageHeight/28); /* default fonts size based on imageHeight */
	imageDepth = bitDepth(); /* required for shadows at different bit depths */
	headings = split(String.getResultsHeadings, "\t"); /* the tab specificity avoids problems with unusual column titles */
	headingsWithRange= newArray;
	for (i=0, countH=0; i<lengthOf(headings); i++) {
		resultsColumn = newArray(items);
		for (j=0; j<items; j++)
			resultsColumn[j] = getResult(headings[i], j);
		Array.getStatistics(resultsColumn, min, max, null, null);
		if (min!=max){ /* No point in listing parameters without a range */
			headingsWithRange[countH] = headings[i] + ":  " + min + " - " + max;
			countH++;
		}
	}
	if (headingsWithRange[0]==" :  Infinity - -Infinity")
		headingsWithRange[0] = "Object" + ":  1 - " + items; /* relabels ImageJ ID column */
	headingsWithRange = Array.trim(headingsWithRange,countH);
	numIntervals = 10; /* default number if intervals in ramp labels - defined here for possible prefs usage later */
	if (imageN>1){  /* workaround for issue with duplicate names for single open image */
		imageList = getList("image.titles");
		for(i=1;i<imageN;i++){
			if (imageList[i]==imageList[i-1]) imageList = Array.deleteIndex(imageList, i);
		}
		imageN = lengthOf(imageList);
	}
	/* Create initial dialog prompt to determine parameters */
	Dialog.create("Parameter Selection");
		/* if called from the BAR menu there will be no macro.filepath so the following checks for that */
		Dialog.addMessage("Macro: " + macroL,10,"#4C4184");
		Dialog.setInsets(0, 20, 0);
		Dialog.addMessage("Filename: " + tNL);
		Dialog.setInsets(0, 20, 0);
		Dialog.addDirectory("Default output directory:",tPath);
		Dialog.setInsets(0, 20, 0);
		Dialog.addMessage("Image has " + nROIs + " ROIs that will be color coded.");
		Dialog.setInsets(0, 20, 10);
		if (imageN==1){
			colImage = t;
			colImageL = lengthOf(colImage);
			if (colImageL>50) colImage = "" + substring(colImage,0,24) + "..." + substring(colImage,colImageL-24);
			Dialog.addMessage("Image for coloring is: " + colImage);
		}
		else if (imageN>5) Dialog.addChoice("Image for color coding", imageList, t);
		else Dialog.addRadioButtonGroup("Choose image for color coding:    ",imageList,imageN,1,imageList[0]);
		Dialog.addChoice("Parameter", headingsWithRange, headingsWithRange[1]);
		luts=getLutsList(); /* I prefer this to new direct use of getList used in the recent versions of the BAR macro YMMV */
		Dialog.addChoice("LUT:", luts, luts[0]);
		Dialog.setInsets(0, 120, 12);
		Dialog.addCheckbox("Reverse LUT?", false);
		Dialog.addMessage("Color Coding:______Borders, Filled ROIs or None \(just labels\)?");
		Dialog.addNumber("Outlines or Solid?", 0, 0, 3, "Width \(pixels\), 0=fill ROIs, -1= label only");
		Dialog.addSlider("Coding opacity (%):", 0, 100, 100);
		outlierOptions = newArray("No", "1sigma", "2sigma","3sigma", "Ramp_Range", "Manual_Input");
		Dialog.addRadioButtonGroup("Outliers: Outline if outside the following values:", outlierOptions, 2, 4, "No");
		Dialog.setInsets(3, 0, 15);
		colorChoicesStd = newArray("red", "green", "blue", "cyan", "magenta", "yellow", "pink", "orange", "violet");
		colorChoicesMod = newArray("garnet", "gold", "aqua_modern", "blue_accent_modern", "blue_dark_modern", "blue_modern", "blue_honolulu", "gray_modern", "green_dark_modern", "green_modern", "green_modern_accent", "green_spring_accent", "orange_modern", "pink_modern", "purple_modern", "red_n_modern", "red_modern", "tan_modern", "violet_modern", "yellow_modern");
		colorChoicesNeon = newArray("jazzberry_jam", "radical_red", "wild_watermelon", "outrageous_orange", "supernova_orange", "atomic_tangerine", "neon_carrot", "sunglow", "laser_lemon", "electric_lime", "screamin'_green", "magic_mint", "blizzard_blue", "dodger_blue", "shocking_pink", "razzle_dazzle_rose", "hot_magenta");
		allColors = Array.concat(colorChoicesStd, colorChoicesMod, colorChoicesNeon);
		Dialog.addChoice("Outliers: Outline color:", allColors, allColors[0]);
		allColors2 = Array.concat("same",allColors);
		Dialog.setInsets(-5,0, 5);
		Dialog.addMessage("Negative sigma \('<'\) outliers can be reported separately and set to a different color:", 12, "#809966");
		Dialog.addChoice("Outliers '<': Outline color:", allColors2, allColors2[0]);
		Dialog.addNumber("Outlier outline thickness:",9,0,3,"% of font size");
		Dialog.addCheckbox("Apply colors and labels to image copy \(no change to original\)", true);
		Dialog.setInsets(6, 120, 10);
		if (selectionExists) {
			tPath = Dialog.getString();
			Dialog.addCheckbox("Summary/Parameter at selected location \(below\)?", true);
			Dialog.addNumber("Starting",selPosStartX,0,5,"X");
			Dialog.setInsets(-28, 150, 0);
			Dialog.addNumber("Starting",selPosStartY,0,5,"Y");
			Dialog.addNumber("Selected",originalSelEWidth,0,5,"Width");
			Dialog.setInsets(-28, 150, 0);
			Dialog.addNumber("Selected",originalSelEHeight,0,5,"Height");
		}
	Dialog.show;
		if (imageN==1) imageChoice = t;
		else if (imageN > 5) imageChoice = Dialog.getChoice();
		else imageChoice = Dialog.getRadioButton();
		parameterWithLabel = Dialog.getChoice;
		parameter = substring(parameterWithLabel, 0, indexOf(parameterWithLabel, ":  "));
		lut = Dialog.getChoice;
		revLut = Dialog.getCheckbox;
		stroke = Dialog.getNumber;
		alpha = pad(toHex(255*Dialog.getNumber/100));
		outlierChoice =  Dialog.getRadioButton;
		if (outlierChoice!="No") sigmaR = (parseInt(substring(outlierChoice,0,1)));
		else sigmaR = NaN;
		outlierColor = Dialog.getChoice(); /* Outline color for outliers */
		outlierColor2 = Dialog.getChoice(); /* Outline color for outliers */
		outlierStrokePC = Dialog.getNumber(); /* default outline stroke: % of font size */
		addLabels = Dialog.getCheckbox;
		if (selectionExists) {
			selectionExists = Dialog.getCheckbox;
			selPosStartX = Dialog.getNumber;
			selPosStartY = Dialog.getNumber;
			originalSelEWidth = Dialog.getNumber;
			originalSelEHeight = Dialog.getNumber;
		}
	selectImage(imageChoice);
	orID = getImageID(); /* update after selection of image */
	t = getTitle();
	if (outlierColor2=="same") outlierColor2 = outlierColor;
	unitLabel = cleanLabel(unitLabelFromString(parameter, unit));
	unitLabel = replace(unitLabel, degreeChar, "degrees"); /* replace lonely ° symbol */
	/* get values for chosen parameter */
	values= newArray(items);
	if (parameter=="Object") for (i=0; i<items; i++) values[i]= i+1;
	else for (i=0; i<items; i++) values[i]= getResult(parameter,i);
	Array.getStatistics(values, arrayMin, arrayMax, arrayMean, arraySD);
	arrayRange = arrayMax-arrayMin;
	rampMin = arrayMin;
	rampMax = arrayMax;
	 /* Just in case parameter still has units appended... */
	pu1 = indexOf(parameter,"\("); pu2 = indexOf(parameter,"\)"); pu3 = indexOf(parameter,"0-90");  /* Exception for 0-90° label */
	if (pu1>0 && pu2>0 && pu3<0) parameterLabel = parameter.substring(0,pu1);
	else parameterLabel = parameter;
	parameterLabelExp = expandLabel(parameterLabel);
	/* Create dialog prompt to determine look */
	Dialog.create("ROI Color Coder: Ramp options: " + macroL);
		Dialog.setInsets(2, 0, 6);
		Dialog.addMessage("Legend \(ramp\) options \(LUT "+lut+"\):");
		Dialog.addString("Parameter label", parameterLabelExp, 3+maxOf(30, lengthOf(parameterLabelExp)));
		Dialog.setInsets(-7, 145, 7);
		Dialog.addMessage("                    Edit for ramp label. Do not include unit in\n Parameter label as it will be added from options below...");
		unitChoices = newArray("Manual", "None");
		unitLinearChoices = newArray(unitLabel, unit, "pixels", "%", "arb.");
		if (unit=="microns" && (unitLabel!=ums || unitLabel!=ums+sup2)) unitLinearChoices = Array.concat(ums,unitLinearChoices);
		unitAngleChoices = newArray(degreeChar, "degrees", "radians");
		unitAreaChoices = newArray(unit+sup2,"pixels"+sup2);
		if (indexOf(parameter,"Area")>=0){
			if (unit=="microns" && (unitLabel!=ums || unitLabel!=ums+sup2)) unitAreaChoices = Array.concat(ums+sup2,unitAreaChoices);
			unitChoices = Array.concat(unitAreaChoices,unitChoices,unitLinearChoices,unitAngleChoices);	
		}
		else if (indexOf(parameter,"Angle")>=0) unitChoices = Array.concat(unitAngleChoices,unitChoices,unitLinearChoices,unitAreaChoices);
		else unitChoices = Array.concat(unitLinearChoices,unitChoices,unitAreaChoices,unitAngleChoices);
		if (unitLabel=="None" || unitLabel=="") dialogUnit = "";
		else dialogUnit = " " + unitLabel;
		Dialog.addChoice("Unit \("+unitLabel+"\) Label:", unitChoices, unitChoices[0]);
		Dialog.setInsets(-38, 300, 0);
		Dialog.addMessage("Default shown is based on\nthe selected parameter");
		Dialog.setInsets(0, 20, -15);
		Dialog.addMessage("Original data range:        "+arrayMin+"-"+arrayMax+" \("+(arrayRange)+" "+dialogUnit+"\)");
		if (outlierChoice=="1sigma") Dialog.addMessage("Outlier range \("+fromCharCode(0x03C3)+"\):        < "+(arrayMean-arraySD)+" > "+(arrayMean+arraySD) + dialogUnit);
		else if (outlierChoice=="2sigma") Dialog.addMessage("Outlier range \(2 "+fromCharCode(0x03C3)+"\):       < "+(arrayMean-2*arraySD)+" > "+(arrayMean+2*arraySD) + dialogUnit);
		else Dialog.addMessage("Outlier range \(3 "+fromCharCode(0x03C3)+"\):       < "+(arrayMean-3*arraySD)+" > "+(arrayMean+3*arraySD) + dialogUnit);
		Dialog.addString("Ramp data range:", rampMin+"-"+rampMax, 20);
		Dialog.addString("LUT range \(n-n format\):", "same as ramp range", 20);
		Dialog.setInsets(-7, 115, 7);
		Dialog.addMessage("                           The LUT gradient will be remapped to this range.\nBeyond this range the top and bottom LUT colors will be applied");
		Dialog.setInsets(-35, 240, 0);
		Dialog.addMessage("(e.g., 10-100)");
		Dialog.setInsets(-4, 120, 0);
		Dialog.addCheckbox("Add ramp labels at Min. & Max. if inside Range", true);
		Dialog.addNumber("No. of intervals:", numIntervals, 0, 3, "Major label count will be +1 more than this");
		Dialog.addNumber("No. of minor ticks between intervals:", 4, 0, 3, "i.e. 5 minor intervals needs 4 minor ticks");
		Dialog.addChoice("Decimal places:", newArray("Auto", "Manual", "Scientific", "0", "1", "2", "3", "4"), "Auto");
		Dialog.addChoice("Ramp height \(pixels\):", newArray(d2s(rampH,0), 128, 256, 512, 1024, 2048, 4096), rampH);
		Dialog.setInsets(-38, 280, 0);
		Dialog.addMessage(rampH + " pixels suggested\nby image height");
		fontStyleChoice = newArray("bold", "bold antialiased", "italic", "italic antialiased", "bold italic", "bold italic antialiased", "unstyled");
		Dialog.addChoice("Font style:", fontStyleChoice, fontStyleChoice[1]);
		fontNameChoice = getFontChoiceList();
		Dialog.addChoice("Font name:", fontNameChoice, fontNameChoice[0]);
		Dialog.addNumber("Font_size \(height\):", fontSize, 0, 3, "pixels");
		Dialog.setInsets(-5, 215, 0);
		Dialog.addCheckbox("Draw border and top/bottom tick marks", true);
		Dialog.setInsets(2, 120, 0);
		Dialog.addCheckbox("Force clockwise rotated legend label", false);
		Dialog.setInsets(3, 0, -2);
		// Dialog.addMessage("Statistics labels added to legend \(ramp\):");
		// Dialog.setInsets(6, 120, -20);
		rampStatsOptions = newArray("No", "Linear", "Ln");
		Dialog.setInsets(-20, 15, 18);
		Dialog.addRadioButtonGroup("Ramp Stats: Mean and " + fromCharCode(0x00B1) + fromCharCode(0x03C3) + " on ramp \(if \"Ln\" then outlier " + fromCharCode(0x03C3) + " will be \"Ln\" too\)", rampStatsOptions, 1, 5, "Linear");
		/* will be used for sigma outlines too */
		Dialog.addNumber("Tick length:", 50, 0, 3, "% of major tick. Also Min. & Max. Lines");
		Dialog.addNumber("Label font:", 100, 0, 3, "% of font size. Also Min. & Max. Lines");
		Dialog.setInsets(4, 120, 0);
		Dialog.addCheckbox("Add Frequency Distribution Plot to Ramp", true);
		binForHoles = is("binary");
		if (binForHoles) Dialog.addCheckbox("Calculate 'Max' image to restore holes \(experimental\)",false);
		else Dialog.addCheckbox("Use binary image of holes to restore holes \(experimental\)",false);
		Dialog.addHelp("https://imagej.net/doku.php?id=macro:roi_color_coder");
	Dialog.show;
		parameterLabel = Dialog.getString;
		unitLabel = Dialog.getChoice();
		if (unitLabel=="None") unitLabel = "";
		rangeS = Dialog.getString; /* changed from original to allow negative values - see below */
		rangeLUT = Dialog.getString;
		if (rangeLUT=="same as ramp range") rangeLUT = rangeS;
		rampMinMaxLines = Dialog.getCheckbox;
		numIntervals = Dialog.getNumber; /* The number intervals along ramp */
		numLabels = numIntervals + 1;  /* The number of major ticks/labels is one more than the intervals */
		minorTicks = Dialog.getNumber; /* The number of minor ticks/labels is one less than the intervals */
		dpChoice = Dialog.getChoice;
		rampHChoice = parseInt(Dialog.getChoice);
		fontStyle = Dialog.getChoice;
		if (fontStyle=="unstyled") fontStyle="";
		fontName = Dialog.getChoice;
		fontSize = Dialog.getNumber;
		brdr = Dialog.getCheckbox;
		rotLegend = Dialog.getCheckbox;
		statsRampLines = Dialog.getRadioButton;
		statsRampTicks = Dialog.getNumber;
		thinLinesFontSTweak = Dialog.getNumber;
		freqDistRamp = Dialog.getCheckbox();
		restoreHoles = Dialog.getCheckbox();
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
	rampUnitLabel = unitLabel.replace("^-","-");
	if (((rotLegend && rampHChoice==rampH)) || (rampW < maxOf(getStringWidth(rampUnitLabel), getStringWidth(rampParameterLabel)))) rampH = imageHeight - fontSize; /* tweaks automatic height selection for vertical legend */
	else rampH = rampHChoice;
	rampW = round(rampH/8);
	range = split(rangeS, "-");
	if (lengthOf(range)==1) {
		rampMin= NaN; rampMax= parseFloat(range[0]);
	} else {
		rampMin= parseFloat(range[0]); rampMax= parseFloat(range[1]);
	}
	if (indexOf(rangeS, "-")==0) rampMin = 0 - rampMin; /* checks to see if rampMin is a negative value (lets hope the rampMax isn't). */
	lutRange = split(rangeLUT, "-");
	if (lengthOf(lutRange)==1) {
		minLUT = NaN; maxLUT = parseFloat(lutRange[0]);
	} else {
		minLUT = parseFloat(lutRange[0]); maxLUT = parseFloat(lutRange[1]);
	}
	if (indexOf(rangeLUT, "-")==0) minLUT = 0 - minLUT; /* checks to see if min is a negative value (lets hope the max isn't). */
	fontSR2 = fontSize * thinLinesFontSTweak/100;
	rampLW = maxOf(1, round(rampH/512)); /* ramp line width with a minimum of 1 pixel */
	minmaxLW = round(rampLW / 4); /* line widths for ramp stats */
	if (isNaN(rampMin)) rampMin = arrayMin;
	if (isNaN(rampMax)) rampMax = arrayMax;
	rampRange = rampMax - rampMin;
	coeffVar = arraySD*100/arrayMean;
	sortedValues = Array.copy(values); sortedValues = Array.sort(sortedValues); /* all this effort to get the median without sorting the original array! */
	arrayQuartile = newArray(3);
	for (q=0; q<3; q++) arrayQuartile[q] = sortedValues[round((q+1)*items/4)];
	IQR = arrayQuartile[2] - arrayQuartile[0];
	mode = NaN;
	autoDistW = NaN;
	/* The following section produces frequency/distribution data for the optional distribution plot on the ramp and for the summary */
	if (IQR>0) {	/* For some data sets IQR can be zero which produces an error in the distribution calculations */
		autoDistW = 2 * IQR * exp((-1/3)*log(items));	/* Uses the optimal binning of Freedman and Diaconis (summarized in [Izenman, 1991]), see https://www.fmrib.ox.ac.uk/datasets/techrep/tr00mj2/tr00mj2/node24.html */
		autoDistWCount = round(arrayRange/autoDistW);
		arrayDistInt = newArray(autoDistWCount);
		arrayDistFreq =  newArray(autoDistWCount);
		modalBin = 0;
		freqMax = 0;
		for (f=0; f<autoDistWCount; f++) {
			arrayDistInt[f] = arrayMin + (f * autoDistW);
			for (i=0; i<items; i++) if ((values[i]>=arrayDistInt[f]) && (values[i]<(arrayDistInt[f]+autoDistW))) arrayDistFreq[f] +=1;
			if (arrayDistFreq[f]>freqMax) { freqMax = arrayDistFreq[f]; modalBin = f;}
		}
		/* use adjacent bin estimate for mode */
		if (modalBin > 0)
			mode = (arrayMin + (modalBin * autoDistW)) + autoDistW * ((arrayDistFreq[modalBin]-arrayDistFreq[maxOf(0,modalBin-1)])/((arrayDistFreq[modalBin]-arrayDistFreq[maxOf(0,modalBin-1)]) + (arrayDistFreq[modalBin]-arrayDistFreq[minOf(arrayDistFreq.length-1,modalBin+1)])));
		Array.getStatistics(arrayDistFreq, freqMin, freqMax, freqMean, freqSD);
		/* End of frequency/distribution section */
	}
	else freqDistRamp = false;
	sIntervalsR = round(rampRange/arraySD);
	meanPlusSDs = newArray(sIntervalsR);
	meanMinusSDs = newArray(sIntervalsR);
	for (s=0; s<sIntervalsR; s++) {
		meanPlusSDs[s] = arrayMean+(s*arraySD);
		meanMinusSDs[s] = arrayMean-(s*arraySD);
	}
	/* Calculate ln stats for summary and also ramp if requested */
	lnValues = lnArray(values);
	Array.getStatistics(lnValues, null, null, lnMean, lnSD);
	expLnMeanPlusSDs = newArray(sIntervalsR);
	expLnMeanMinusSDs = newArray(sIntervalsR);
	expLnSD = exp(lnSD);
	for (s=0; s<sIntervalsR; s++) {
		expLnMeanPlusSDs[s] = exp(lnMean+s*lnSD);
		expLnMeanMinusSDs[s] = exp(lnMean-s*lnSD);
	}
	/* Create the parameter label */
	if (unitLabel=="Manual") {
		unitLabel = unitLabelFromString(parameter, unit);
			Dialog.create("Manual unit input");
			Dialog.addString("Label:", unitLabel, 8);
			Dialog.addMessage("^2 & um etc. replaced by " + fromCharCode(178) + " & " + fromCharCode(181) + "m...");
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
		tickLR = round(tickL * statsRampTicks/100);
		getLocationAndSize(imgx, imgy, imgwidth, imgheight);
		call("ij.gui.ImageWindow.setNextLocation", imgx + imgwidth, imgy);
		tR = replace(tN + "_" + parameterLabel +"_Ramp", " ","_");
		newImage(tR, "ramp", rampH, rampW, "8-bit"); /* Height and width swapped for later rotation */
		/* ramp color/gray range is horizontal only so must be rotated later */
		if (revLut) run("Flip Horizontally");
		tR = getTitle; /* short variable label for ramp */
		run(lut);
		/* modify lut if requested */
		if (rangeLUT!=rangeS) { /* recode legend if LUT over restricted range */
			if (minLUT<rampMin || maxLUT>rampMax) exit("Sorry, the LUT range must be the same or within the ramp range");
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
			setLut(newReds, newGreens,newBlues);
		}
		roiColors = hexLutColors(); /* creates a hexColor array: requires function */
		/* continue the legend design */
		/* Frequency line if requested */
		if (freqDistRamp) {
			rampRXF = rampH/(rampRange); /* RXF short for Range X Factor Units/pixel */
			rampRYF = (rampW-2*rampLW)/freqMax; /* RYF short for Range Y Factor Freg/pixel - scale from zero */
			distFreqPosX = newArray(autoDistWCount);
			distFreqPosY = newArray(autoDistWCount);
			for (f=0; f<(autoDistWCount); f++) {
				distFreqPosX[f] = (arrayDistInt[f]-rampMin)*rampRXF;
				distFreqPosY[f] = arrayDistFreq[f]*rampRYF;
			}
			distFreqPosXIncr = distFreqPosX[autoDistWCount-1] - distFreqPosX[autoDistWCount-2];
			fLastX = newArray(distFreqPosX[autoDistWCount-1]+distFreqPosXIncr,"");
			distFreqPosX = Array.concat(distFreqPosX,fLastX);
			freqDLW = maxOf(1,round(rampLW/2));
			setLineWidth(freqDLW);
			for (f=0; f<(autoDistWCount); f++) { /* Draw All Shadows First */
				setColor(0, 0, 0); /* Note that this color will be converted to LUT equivalent */
				if (arrayDistFreq[f] > 0) {
					drawLine(distFreqPosX[f]-freqDLW, freqDLW, distFreqPosX[f]-freqDLW, distFreqPosY[f]-freqDLW);
					drawLine(distFreqPosX[f]-freqDLW, distFreqPosY[f]-freqDLW, distFreqPosX[f+1]-freqDLW, distFreqPosY[f]-freqDLW); /* Draw bar top */
					drawLine(distFreqPosX[f+1]-freqDLW, freqDLW, distFreqPosX[f+1]-freqDLW, distFreqPosY[f]-freqDLW); /* Draw bar side */
				}
			}
			for (f=0; f<autoDistWCount; f++) {
				setColor(255, 255, 255); /* Note that this color will be converted to LUT equivalent */
				if (arrayDistFreq[f] > 0) {
					drawLine(distFreqPosX[f], freqDLW, distFreqPosX[f], distFreqPosY[f]);  /* Draw bar side - right/bottom */
					drawLine(distFreqPosX[f], distFreqPosY[f], distFreqPosX[f+1], distFreqPosY[f]); /* Draw bar cap */
					drawLine(distFreqPosX[f+1], freqDLW, distFreqPosX[f+1],distFreqPosY[f]); /* Draw bar side - left/top */
				}
			}
		}
		setColor(0, 0, 0);
		setBackgroundColor(255, 255, 255);
		numLabelFontSize = minOf(fontSize, rampH/numLabels);
		if ((numLabelFontSize<10) && acceptMinFontSize) numLabelFontSize = maxOf(10, numLabelFontSize);
		setFont(fontName, numLabelFontSize, fontStyle);
		if (imageDepth!=8 || lut!="Grays") run("RGB Color"); /* converts ramp to RGB if not using grays only */
		setLineWidth(rampLW*2);
		if (brdr) {
			drawRect(0, 0, rampH, rampW);
			/* The next steps add the top and bottom ticks */
			rampWT = rampW + 2*rampLW;
			run("Canvas Size...", "width=&rampH height=&rampWT position=Top-Center");
			setLineWidth(rampLW*1.5);
			drawLine(0, 0, 0, rampW-1 + rampLW); /* Draw full width line at top an bottom */
			drawLine(rampH-1, 0, rampH-1, rampW-1 + rampLW); /* Draw full width line at top an d bottom */
		}
		run("Rotate 90 Degrees Left");
		run("Canvas Size...", "width="+canvasW+" height="+canvasH+" position=Center-Left");
		if (dpChoice=="Auto")
			decPlaces = autoCalculateDecPlaces3(rampMin,rampMax,numIntervals);
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
		/* Create array of ramp labels that can be used to optimize label length */
		rampLabelString = newArray;
		for (i=0,maxDP=0; i<numLabels; i++) {
			rampLabel = rampMin + i * stepV;
			rampLabelString[i] = d2s(rampLabel,decPlaces);
		}
		if (dpChoice=="Auto"){
			/* Remove excess zeros from ramp labels but not if manually set
			Note that this is not the broader range trimming of the
			removeTrailingZerosAndPeriod function because it limits to one iteration.
			*/
			for (i=0; i<decPlaces; i++) {
				for (j=0,countL=0; j<numLabels; j++){
					iP = indexOf(rampLabelString[j], ".");
					if (endsWith(rampLabelString[i],"0") && iP>0) countL++;
				}
				if (countL==numLabels){
					for (j=0; j<numLabels; j++){
						rampLabelString[j] = "" + remTZeroP(rampLabelString[j],2);
					}
				}
			}
		}
		/* clean up top and bottom labels are special cases even in non-auto mode */
		while(indexOf(rampLabelString[0],".")>0 && endsWith(rampLabelString[0],"0"))
			rampLabelString[0] = substring(rampLabelString[0],0,lengthOf(rampLabelString[0])-1);
		if	(endsWith(rampLabelString[0],".")) rampLabelString[0] = substring(rampLabelString[0],0,lengthOf(rampLabelString[0])-1);
		while(indexOf(rampLabelString[numLabels-1],".")>0 && endsWith(rampLabelString[numLabels-1],"0"))
			rampLabelString[numLabels-1] = substring(rampLabelString[numLabels-1],0,lengthOf(rampLabelString[numLabels-1])-1);
		if	(endsWith(rampLabelString[numLabels-1],".")) rampLabelString[numLabels-1] = substring(rampLabelString[numLabels-1],0,lengthOf(rampLabelString[numLabels-1])-1);
		/* end of ramp number label cleanup */
		setLineWidth(rampLW);
		for (i=0; i<numLabels; i++) {
			yPos = rampH + rampOffset - i*step -1; /* minus 1 corrects for coordinates starting at zero */
			/*Now add overrun text labels at the top and/or bottom of the ramp if the true data extends beyond the ramp range */
			if (i==0 && rampMin>(1.001*arrayMin))
				rampLabelString[i] = fromCharCode(0x2264) + rampLabelString[i];
			if (i==(numLabels-1) && rampMax<(0.999*arrayMax))
				rampLabelString[i] = fromCharCode(0x2265) + rampLabelString[i];
			drawString(rampLabelString[i], rampW+4*rampLW, yPos+numLabelFontSize/1.5);
			/* major ticks are not optional in this version as they are needed to make sense of the ramp labels */
			if ((i>0) && (i<(numIntervals))) {
				setLineWidth(rampLW);
				drawLine(0, yPos, tickL, yPos);					/* left tick */
				drawLine(rampW-1-tickL, yPos, rampW, yPos);
				drawLine(rampW, yPos, rampW+rampLW, yPos); /* right tick extends over border slightly as subtle cross-tick */
			}
			/* end of ramp major tick drawing */
		}
		setFont(fontName, fontSize, fontStyle);
		/* draw minor ticks */
		if (minorTicks>0) {
			minorTickStep = step/(minorTicks+1);
			numTick = numLabels + numIntervals*minorTicks - 1; /* no top tick */
			for (i=1; i<numTick; i++) { /* no bottom tick */
				yPos = rampH + rampOffset - i*minorTickStep -1; /* minus 1 corrects for coordinates starting at zero */
					setLineWidth(round(rampLW/4));
					drawLine(0, yPos, tickL/4, yPos);					/* left minor tick */
					drawLine(rampW-tickL/4-1, yPos, rampW-1, yPos);		/* right minor tick */
			}
		}
		/* end draw minor ticks */
		/* now add lines and the true min and max and for stats if chosen in previous dialog */
		if ((0.98*rampMin<=arrayMin) && (0.98*rampMax<=arrayMax)) rampMinMaxLines = false;
		if ((rampMin>arrayMin) && (rampMax<arrayMax)) rampMinMaxLines = false;
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
				if ((trueMaxFactor<1) && (maxPos<(rampH - 0.5*fontSR2))) {
					setFont(fontName, fontSR2, fontStyle);
					stringY = round(maxOf(maxPos+0.75*fontSR2,rampTBMargin+0.75*fontSR2));
					drawString("Max", round((rampW-getStringWidth("Max"))/2), stringY);
					drawLine(rampLW, maxPos, tickLR, maxPos);
					drawLine(rampW-1-tickLR, maxPos, rampW-rampLW-1, maxPos);
				}
				if ((trueMinFactor>0) && (minPos>(0.5*fontSR2))) {
					setFont(fontName, fontSR2, fontStyle);
					stringY = round(minOf(minPos+0.75*fontSR2,rampTBMargin+rampH-0.25*fontSR2));
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
				if ((rampMeanPlusSDs[0]>(rampMin+0.2*rampRange)) && ((rampMeanPlusSDs[0]-rampMin)<=(0.92*rampRange))) {
					drawString("Mean", round((rampW-getStringWidth("Mean"))/2), plusSDPos[0]+0.75*meanFS);
					drawLine(rampLW, plusSDPos[0], tickLR, plusSDPos[0]);
					drawLine(rampW-1-tickLR, plusSDPos[0], rampW-rampLW-1, plusSDPos[0]);
				}
				else print("Warning: Mean not drawn on ramp as determined to be to be out of filled ramp range");
				lastDrawnPlusSDPos = plusSDPos[0];
				sPLimit = lengthOf(rampMeanPlusSDFactors)-1; /* should be sIntervalsR but this was a voodoo fix for some issue here */
				sMLimit = lengthOf(rampMeanMinusSDFactors)-1; /* should be sIntervalsR but this was a voodoo fix for some issue here */
				for (s=1; s<sIntervalsR; s++) {
					if ((rampMeanPlusSDFactors[minOf(sPLimit,s)]<=1) && (plusSDPos[s]<=(rampH - fontSR2)) && (abs(plusSDPos[s]-lastDrawnPlusSDPos)>0.75*fontSR2)) {
						setFont(fontName, fontSR2, fontStyle);
						if (rampMinMaxLines) {
							if (plusSDPos[s]<=(maxPos-0.9*fontSR2) || plusSDPos[s]>=(maxPos+0.9*fontSR2)) { /* prevent overlap with max line */
								drawString("+"+s+fromCharCode(0x03C3), round((rampW-getStringWidth("+"+s+fromCharCode(0x03C3)))/2), round(plusSDPos[s]+0.75*fontSR2));
								drawLine(rampLW, plusSDPos[s], tickLR, plusSDPos[s]);
								drawLine(rampW-1-tickLR, plusSDPos[s], rampW-rampLW-1, plusSDPos[s]);
								lastDrawnPlusSDPos = plusSDPos[s];
							}
						}
						else {
							drawString("+"+s+fromCharCode(0x03C3), round((rampW-getStringWidth("+"+s+fromCharCode(0x03C3)))/2), round(plusSDPos[s]+0.75*fontSR2));
							drawLine(rampLW, plusSDPos[s], tickLR, plusSDPos[s]);
							drawLine(rampW-1-tickLR, plusSDPos[s], rampW-rampLW-1, plusSDPos[s]);
							lastDrawnPlusSDPos = plusSDPos[s];
						}
						if (rampMeanPlusSDFactors[minOf(sPLimit,minOf(sIntervalsR,s+1))]>=0.98) s = sIntervalsR;
					}
				}
				lastDrawnMinusSDPos = minusSDPos[0];
				for (s=1; s<sIntervalsR; s++) {
					if ((rampMeanMinusSDFactors[minOf(sPLimit,s)]>0) && (minusSDPos[s]>fontSR2) && (abs(minusSDPos[s]-lastDrawnMinusSDPos)>0.75*fontSR2)) {
						setFont(fontName, fontSR2, fontStyle);
						if (rampMinMaxLines) {
							if ((minusSDPos[s]<(minPos-0.9*fontSR2)) || (minusSDPos[s]>(minPos+0.9*fontSR2))) { /* prevent overlap with min line */
								drawString("-"+s+fromCharCode(0x03C3), round((rampW-getStringWidth("-"+s+fromCharCode(0x03C3)))/2), round(minusSDPos[s]+0.5*fontSR2));
								drawLine(rampLW, minusSDPos[s], tickLR, minusSDPos[s]);
								drawLine(rampW-1-tickLR, minusSDPos[s], rampW-rampLW-1, minusSDPos[s]);
								lastDrawnMinusSDPos = minusSDPos[s];
							}
						}
						else {
							drawString("-"+s+fromCharCode(0x03C3), round((rampW-getStringWidth("-"+s+fromCharCode(0x03C3)))/2), round(minusSDPos[s]+0.5*fontSR2));
							drawLine(rampLW, minusSDPos[s], tickLR, minusSDPos[s]);
							drawLine(rampW-1-tickLR, minusSDPos[s], rampW-rampLW-1, minusSDPos[s]);
							lastDrawnMinusSDPos = minusSDPos[s];
						}
						if (rampMeanMinusSDs[minOf(sMLimit,minOf(sIntervalsR,s+1))]<0.93*rampMin) s = sIntervalsR;
					}
				}
			}
			run("Duplicate...", "title=stats_text");
			/* now use a mask to create black outline around white text to stand out against ramp colors */
			selectWindow("label_mask");
			rampOutlineStroke = maxOf(1,round(rampLW/2));
			setThreshold(0, 128);
			setOption("BlackBackground", false);
			run("Convert to Mask");
			selectWindow(tR);
			run("Select None");
			getSelectionFromMask("label_mask");
			getSelectionBounds(maskX, maskY, null, null);
			if (rampOutlineStroke>0) rampOutlineOffset = maxOf(0, (rampOutlineStroke/2)-1);
			setSelectionLocation(maskX+rampOutlineStroke, maskY+rampOutlineStroke); /* Offset selection to create shadow effect */
			run("Enlarge...", "enlarge="+rampOutlineStroke+" pixel");
			setBackgroundColor(0, 0, 0);
			run("Clear");
			run("Enlarge...", "enlarge="+rampOutlineStroke+" pixel");
			run("Gaussian Blur...", "sigma="+rampOutlineStroke);
			run("Select None");
			getSelectionFromMask("label_mask");
			setBackgroundColor(255, 255, 255);
			run("Clear");
			run("Select None");
			/* The following steps smooth the interior of the text labels */
			selectWindow("stats_text");
			getSelectionFromMask("label_mask");
			if (selectionType()>=0) run("Make Inverse");
			else restoreExit("Ramp creation: No selection to invert");
			run("Invert");
			run("Select None");
			imageCalculator("Min",tR,"stats_text");
			closeImageByTitle("label_mask");
			closeImageByTitle("stats_text");
			/* reset colors and font */
			setFont(fontName, fontSize, fontStyle);
			setColor(0,0,0);
			/* Color right sigma tick mark with outlier color for outlier range */
			if(statsRampLines!="No"){
				lastDrawnPlusSDPos = plusSDPos[0];
				setColorFromColorName(outlierColor);
				for (s=1; s<sIntervalsR; s++) {
					if ((outlierChoice!="No") && (s>=sigmaR)) {
						if ((rampMeanPlusSDFactors[minOf(sPLimit,s)]<=1) && (plusSDPos[s]<=(rampH - fontSR2)) && (abs(plusSDPos[s]-lastDrawnPlusSDPos)>0.75*fontSR2)) {
							if (rampMinMaxLines) {
								if ((plusSDPos[s]<=(maxPos-0.75*fontSR2)) || (plusSDPos[s]>=(maxPos+0.75*fontSR2))) { /* prevent overlap with max line */
									drawLine(rampW-1-tickLR, plusSDPos[s]+rampLW*0.75, rampW-rampLW-1, plusSDPos[s]+rampLW*0.75);
									drawLine(rampW-1-tickLR, plusSDPos[s]-rampLW*0.75, rampW-rampLW-1, plusSDPos[s]-rampLW*0.75);
								}
							}
							else {
								drawLine(rampW-1-tickLR, plusSDPos[s]+rampLW*0.75, rampW-rampLW-1, plusSDPos[s]+rampLW*0.75);
								drawLine(rampW-1-tickLR, plusSDPos[s]-rampLW*0.75, rampW-rampLW-1, plusSDPos[s]-rampLW*0.75);
								lastDrawnPlusSDPos = plusSDPos[s];
							}
							if (rampMeanPlusSDFactors[minOf(sPLimit,minOf(sIntervalsR,s+1))]>=0.98) s = sIntervalsR;
						}
					}
				}
				setColorFromColorName(outlierColor2);
				lastDrawnMinusSDPos = minusSDPos[0];
				for (s=1; s<sIntervalsR; s++) {
					if ((outlierChoice!="No") && (s>=sigmaR)) {
						if ((rampMeanMinusSDFactors[minOf(sMLimit,s)]>0) && (minusSDPos[s]>fontSR2) && (abs(minusSDPos[s]-lastDrawnMinusSDPos)>0.75*fontSR2)) {
							if (rampMinMaxLines) {
								if (minusSDPos[s]<(minPos-0.75*fontSR2) || minusSDPos[s]>(minPos+0.75*fontSR2)) { /* prevent overlap with min line */
									drawLine(rampW-1-tickLR, minusSDPos[s]+rampLW*0.75, rampW-rampLW-1, minusSDPos[s]+rampLW*0.75);
									drawLine(rampW-1-tickLR, minusSDPos[s]-rampLW*0.75, rampW-rampLW-1, minusSDPos[s]-rampLW*0.75);
									lastDrawnMinusSDPos = minusSDPos[s];
								}
							}
							else {
								drawLine(rampW-1-tickLR, minusSDPos[s]+rampLW*0.75, rampW-rampLW-1, minusSDPos[s]+rampLW*0.75);
								drawLine(rampW-1-tickLR, minusSDPos[s]-rampLW*0.75, rampW-rampLW-1, minusSDPos[s]-rampLW*0.75);
								lastDrawnMinusSDPos = minusSDPos[s];
							}
							if (rampMeanMinusSDs[minOf(sMLimit,minOf(sIntervalsR,s+1))]<0.93*rampMin) s = sIntervalsR;
						}
					}
				}
			}
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
			if (rampUnitLabel!="") rampParameterLabel += ", " + rampUnitLabel;
			run("Canvas Size...", "width="+canvasH+" height="+canvasW+" position=Bottom-Center");
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
		run("Canvas Size...", "width="+canvasW+" height="+canvasH+" position=Center");
		/*
			iterate through the ROI Manager list and colorize ROIs
		*/
		selectImage(orID);
		/* iterate through the ROI Manager list and colorize ROIs */
		for (countNaN=0, i=0; i<items; i++) {
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
			roiManager("select", i);
			if (stroke>0) {
				roiManager("Set Line Width", stroke);
				roiManager("Set Color", alpha+roiColors[lutIndex]);
			} else
				roiManager("Set Fill Color", alpha+roiColors[lutIndex]);
			labelString = d2s(values[i],decPlaces); /* Reduce decimal places for labeling (move these two lines to below the labels you prefer) */
			labelString = removeTrailingZerosAndPeriod(labelString); /* Remove trailing zeros and periods */
		}
	}
	else IJ.log("Stroke not set");
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
		if (restoreHoles && binForHoles) { /* Not fully tested yet but should be harmless */
			mI1 = getImageID();
			roiManager("show all without labels");
			run("Flatten");
			mI1F = getTitle();
			imageCalculator("Max", mI1F,orID);
			// run("Image Calculator...");
			closeImageByTitle(mI1);
			selectWindow(mI1F);
			rename(tN);
		}
		selectWindow(tN);
		roiManager("show all with labels");
		run("Flatten"); /* creates an RGB copy of the image with color coded objects or not */
		if (restoreHoles && !binForHoles){
			holesPath = File.openDialog("Select an image of the holes");
			open(holesPath);
			rename(holesTemp);
			run("Convert to Mask");
			getSelectionFromMask(holesTemp);
			run("Select None");
			close(holesTemp);
			selectImage(orID);
			run("Restore Selection");
			run("Copy");
			selectWindow(tN);
			run("Restore Selection");
			run("Paste");
			run("Select None");
		}
	}
	else {
		roiManager("Show All without labels");
		/* Now to add scaled object labels */
		/* First: set default label settings */
		shadowDropPC = 10;  /* default outer shadow drop: % of font size */
		dIShOPC = 4; /* default inner shadow drop: % of font size */
		offsetX = maxOf(1, round(imageWidth/150)); /* default offset of label from edge */
		offsetY = maxOf(1, round(imageHeight/150)); /* default offset of label from edge */
		fontColor = "white";
		outlineColor = "black";
		paraLabFontSize = round((imageHeight+imageWidth)/75);
		if ((paraLabFontSize<10) && acceptMinFontSize) paraLabFontSize = 11;
		statsLabFontSize = round((imageHeight+imageWidth)/100);
		if ((statsLabFontSize<10) && acceptMinFontSize) statsLabFontSize = 10;
		/* Feature Label Formatting Options Dialog . . . */
		Dialog.create("Feature Label Formatting Options");
			Dialog.setInsets(0, 150, 6);
			Dialog.addCheckbox("Add feature labels to each ROI?", false);
			allGrays = newArray("white", "black", "off-white", "off-black", "light_gray", "gray", "dark_gray");
			if (lut!="Grays")
				colorChoices = Array.concat(allGrays,allColors);
			else colorChoices = allGrays;
			iColor = indexOfArray(colorChoices, call("ij.Prefs.get", "fancyColorCoder.objectFontColor",colorChoices[0]),0);
			Dialog.addChoice("Object label color:", colorChoices, iColor);
			Dialog.addNumber("Font scaling:", 60,0,3,"\% of auto \(" + round(fontSize) + "\)");
			minROIFont = round(imageWidth/90);
			if ((minROIFont<10) && acceptMinFontSize) minROIFont = 10;
			Dialog.addNumber("Restrict label font size:", minROIFont,0,4, "Min to ");
			Dialog.setInsets(-28, 90, 0);
			maxROIFont = round(imageWidth/16);
			if ((maxROIFont<10) && acceptMinFontSize) maxROIFont = 10;
			Dialog.addNumber("Max", maxROIFont, 0, 4, "Max");
			fontStyleChoice = newArray("bold", "bold antialiased", "italic", "bold italic", "unstyled");
			Dialog.addChoice("Font style:", fontStyleChoice, fontStyleChoice[1]);  /* Reuse font list from previous dialog */
			Dialog.addChoice("Font name:", fontNameChoice, fontName); /* Default to previous fontName */
			Dialog.addChoice("Decimal places \(Fixed_Auto="+decPlaces+"\):", newArray("Fixed_Auto","Auto_Trimmed", "Manual", "Scientific", "0", "1", "2"), "Fixed_Auto"); /* reuse previous dpChoice as default */
			Dialog.setInsets(-6, 100, 6);
			Dialog.addMessage("Auto_Trimmed removes point-trailing zeros");
			Dialog.addNumber("Label outline stroke:", outlineStrokePC,0,3,"% of auto mean size");
			iColor = indexOfArray(colorChoices,  call("ij.Prefs.get", "fancyColorCoder.objectOutlineColor",colorChoices[1]),0);
			Dialog.addChoice("Label Outline (background) color:", colorChoices, colorChoices[iColor]);
			if (menuLimit > 796){
				Dialog.addNumber("Shadow drop: "+fromCharCode(0x00B1), shadowDropPC,0,3,"% of mean font size");
				Dialog.addNumber("Shadow displacement Right: "+fromCharCode(0x00B1), shadowDropPC,0,3,"% of mean font size");
				Dialog.addNumber("Shadow Gaussian blur:", floor(0.75 * shadowDropPC),0,3,"% of mean font size");
				Dialog.addNumber("Shadow darkness \(darkest = 100%\):", 50,0,3,"%, neg.= glow");
			}
			else Dialog.addCheckbox("Tweak label format?", false);
			fancyInnerEffectsChoices = newArray("None", "Recessed", "Raised");
			fancyInnerEffectsChoice = call("ij.Prefs.get", "fancyColorCoder.innerEffects","None");
			Dialog.addChoice("Inner text effects:",fancyInnerEffectsChoices,fancyInnerEffectsChoice);
			Dialog.setInsets(3, 0, 3);
			if (isNaN(getResult("mc_X\(px\)",0)) && (checkForPlugin("morphology_collection"))) {
				Dialog.addChoice("Object labels at: ", newArray("ROI Center", "Morphological Center"), "ROI Center");
				Dialog.setInsets(-3, 40, 6);
				Dialog.addMessage("If selected, morphological centers will be added to the results table.");
			}
			else if (isNaN(getResult("mc_X\(px\)",0)) && (!checkForPlugin("morphology_collection"))) {
				Dialog.addChoice("Object labels at: ", newArray("ROI Center"), "ROI Center");
				Dialog.setInsets(-3, 40, 6);
				Dialog.addMessage("Morphology plugin not available to find morphological centers");
			}
			else Dialog.addChoice("Object Label At:", newArray("ROI Center", "Morphological Center"), "Morphological Center");
			paraLabAdd = call("ij.Prefs.get", "fancyColorCoder.paraLabAdd",false);
			Dialog.addCheckbox("Add Parameter Label Title: \("+paraLabel+"\)?", paraLabAdd);
			summaryOutputChecks = newArray("Summary->Image","Summary->Log","Summary->File");
			summaryToImage = call("ij.Prefs.get", "fancyColorCoder.summaryToImage",false);
			summaryToLog = call("ij.Prefs.get", "fancyColorCoder.summaryToLog",true);
			summaryToFile = call("ij.Prefs.get", "fancyColorCoder.summaryToFile",true);
			Dialog.addCheckboxGroup(1,3,summaryOutputChecks,newArray(summaryToImage,summaryToLog,summaryToFile));
			if (selectionExists) paraLocChoice = newArray("Current Selection", "Top Left", "Top Right", "Center", "Bottom Left", "Bottom Right", "At New Selection");
			else paraLocChoice = newArray("Top Left", "Top Right", "Center", "Bottom Left", "Bottom Right", "At New Selection");
			Dialog.addChoice("Title and Summary table Location:", paraLocChoice, paraLocChoice[0]);
			if (menuLimit > 752)	Dialog.addNumber("How many rows in table?", 16, 0, 2, "");
			else Dialog.addNumber("How many rows in table?", 8, 0, 2, "");
		Dialog.show();
			addLabels = Dialog.getCheckbox;
			fontColor = Dialog.getChoice(); /* Object label color */
			call("ij.Prefs.set", "fancyColorCoder.objectFontColor",fontColor);
			fontSCorrection = (Dialog.getNumber)/100;
			minLFontS = Dialog.getNumber();
			maxLFontS = Dialog.getNumber();
			fontStyle = Dialog.getChoice();
			fontName = Dialog.getChoice();
			call("ij.Prefs.set", "objFCol",fontName);
			dpChoice = Dialog.getChoice();
			outlineStrokePC = Dialog.getNumber();
			outlineColor = Dialog.getChoice();
			call("ij.Prefs.set", "fancyColorCoder.objectOutlineColor",outlineColor);
			if (menuLimit > 800){
				shadowDrop = Dialog.getNumber();
				shadowDisp = Dialog.getNumber();
				shadowBlur = Dialog.getNumber();
				shadowDarkness = Dialog.getNumber();
				tweakLabels = false;
			}
			else tweakLabels = Dialog.getCheckbox();
			innerTextEffect = Dialog.getChoice();
			call("ij.Prefs.set", "fancyColorCoder.innerEffects",innerTextEffect);
			ctrChoice = Dialog.getChoice(); /* Choose ROI or morphological centers for object labels */
			paraLabAdd = Dialog.getCheckbox();
			call("ij.Prefs.set", "fancyColorCoder.paraLabAdd",paraLabAdd);
			summaryToImage = Dialog.getCheckbox();
			call("ij.Prefs.set", "fancyColorCoder.summaryToImage",summaryToImage);
			summaryToLog = Dialog.getCheckbox();
			call("ij.Prefs.set", "fancyColorCoder.summaryToLog",summaryToLog);
			summaryToFile = Dialog.getCheckbox();
			call("ij.Prefs.set", "fancyColorCoder.summaryToFile",summaryToFile);
			summaryChoice = "";
			if (summaryToImage || summaryToLog || summaryToFile){
				summaryAdd = true;
				if (summaryToImage) summaryChoice += "to image, ";
				if (summaryToLog) summaryChoice += "to log, ";
				if (summaryToFile) summaryChoice += "to file, ";
				summaryChoice += "end";
				summaryChoice = replace(summaryChoice,", end","");
			} 
			else summaryAdd = false;
			paraLabPos = Dialog.getChoice(); /* Parameter Label Position */
			statsChoiceLines = Dialog.getNumber();
		if (menuLimit <= 796){
			if (tweakLabels){
				Dialog.create("Label tweak options for low resolution monitors");
					Dialog.addNumber("Shadow drop: "+fromCharCode(0x00B1), shadowDropPC,0,3,"% of mean font size");
					Dialog.addNumber("Shadow displacement Right: "+fromCharCode(0x00B1), shadowDropPC,0,3,"% of mean font size");
					Dialog.addNumber("Shadow Gaussian blur:", floor(0.75 * shadowDropPC),0,3,"% of mean font size");
					Dialog.addNumber("Shadow darkness \(darkest = 100%\):", 50,0,3,"%, neg.= glow");
				Dialog.show();
					shadowDrop = Dialog.getNumber();
					shadowDisp = Dialog.getNumber();
					shadowBlur = Dialog.getNumber();
					shadowDarkness = Dialog.getNumber();
			}
			else {  /* set the default values if no tweaking and lo-res monitor */
				shadowDrop = shadowDropPC;
				shadowDisp = shadowDropPC;
				shadowBlur = 0.75 * shadowDropPC;
				shadowDarkness = 50;
			}
		}
		if (isNaN(getResult("mc_X\(px\)",0)) && (ctrChoice=="Morphological Center")){
			if (!is("binary")){
				run("Duplicate...", "title=temp_binary_for_MCs");
				run("8-bit");
				AddMCsToResultsTable();
				closeImageByTitle("temp_binary_for_MCs");
			}
			else AddMCsToResultsTable();
		}
		selectWindow(t);
		if (dpChoice=="Manual")
			decPlaces = getNumber("Choose Number of Decimal Places", decPlaces);
		else if (dpChoice=="Scientific")
			decPlaces = -1;
		else if (dpChoice!="Auto_Trimmed" && dpChoice!="Fixed_Auto")
			decPlaces = dpChoice;
		if (fontStyle=="unstyled") fontStyle="";
		if (stroke>=0) {
			run("Flatten"); /* Flatten converts to RGB so . . .  */
			if (restoreHoles){
				if (binForHoles) {  /* To overcome issue of complete ROI-fill, not fully tested yet */
					mI1i = getImageID();
					run("Flatten");
					rename("flatImage");
					mI1Fi = getImageID();
					imageCalculator("Max", "flatImage",orID);
					if (mI1i!=mI1Fi){
						selectImage(mI1i);
						close();
					}
					selectWindow("flatImage");
				}
				else {
					preHolesID = getImageID();
					holesPath = File.openDialog("Select an image of the holes");
					open(holesPath);
					rename("holesTemp");
					run("Convert to Mask");
					getSelectionFromMask("holesTemp");
					run("Select None");
					close("holesTemp");
					selectImage(orID);
					run("Restore Selection");
					run("Copy");
					selectImage(preHolesID);
					run("Restore Selection");
					run("Paste");
					run("Select None");
				}
			}
			rename(tN + "_" + parameterLabel + "_labels");
			if ((imageDepth==8) && (lut=="Grays")) run("8-bit"); /* restores gray if all gray settings */
		} else {
			run("Duplicate...", "title=labeled");
			if (restoreHoles){ /* Not fully tested yet but should be harmless */
				if (binForHoles) imageCalculator("Max", "labeled",orID);
				// run("Image Calculator...");
				// setBatchMode("exit & display");
				// waitForUser("OK 961?");
				// setBatchMode(true);
				else {
					holesPath = File.openDialog("Select an image of the holes");
					open(holesPath);
					rename("holesTemp");
					run("Convert to Mask");
					getSelectionFromMask("holesTemp");
					run("Select None");
					close("holesTemp");
					selectImage(orID);
					run("Restore Selection");
					run("Copy");
					selectWindow(labeled);
					run("Restore Selection");
					run("Paste");
					run("Select None");
				}
			}
			rename(tN + "_" + parameterLabel + "_labels");
		}
		workingImage = getTitle();
		if (is("Batch Mode")==false) setBatchMode(true);
		if (outlierChoice!="No")  {
			if (outlierChoice=="Manual_Input") {
				Dialog.create("Input Outlier Limits");
				Dialog.addString("Outlier Limits:", "Low-High", 16);
				Dialog.addMessage("Alternatively enter 4sigma, 5sigma etc. \(up to 9\).");
				Dialog.show();
				outlierLimit = Dialog.getString();
				sigmaTest = split(outlierLimit,"sig");
				if (lengthOf(sigmaTest)>1) {
					sigmaR = (parseInt(substring(outlierLimit,0,1)));
					outlierChoice = "" + sigmaR + "sigma";
				}
				else {
					outlierLimits = split(outlierLimit, "-");
					if (lengthOf(outlierLimits)==1) {
						outlierMin= NaN; outlierMax= parseFloat(range[0]);
					} else {
						outlierMin= parseFloat(outlierLimits[0]); outlierMax= parseFloat(outlierLimits[1]);
					}
					if (indexOf(outlierChoice, "-")==0) outlierMin = 0 - outlierMin; /* checks to see if rampMin is a negative value (lets hope the rampMax isn't). */
				}
			}
			outlierStroke = maxOf(1,round(fontSize/100 * outlierStrokePC));
			run("Line Width...", "line="+outlierStroke);
			for (i=0,outlierCounterPos=0,outlierCounterNeg=0; i<items; i++) {
				roiManager("select", i);
				if (outlierChoice=="Ramp_Range") {
					if (values[i]>rampMax) {
						setForegroundColorFromName(outlierColor);
						run("Draw", "slice");
						outlierCounterPos++;
					}
					if (values[i]<rampMin) {
						setForegroundColorFromName(outlierColor2);
						run("Draw", "slice");
						outlierCounterNeg++;
					}
				}
				else if (outlierChoice=="Manual_Input") {
					if (values[i]>outlierMax) {
						setForegroundColorFromName(outlierColor);
						run("Draw", "slice");
						outlierCounterPos++;
					}
					if (values[i]<outlierMin) {
						setForegroundColorFromName(outlierColor2);
						run("Draw", "slice");
						outlierCounterNeg++;
					}
				}
				else if (sigmaR>=1) {
					if (statsRampLines=="Ln") {
						if (values[i]>(expLnMeanPlusSDs[minOf(sIntervalsR-1,sigmaR)])) {
							setForegroundColorFromName(outlierColor);
							run("Draw", "slice");
							outlierCounterPos++;
						}
						if (values[i]<(expLnMeanMinusSDs[minOf(sIntervalsR-1,sigmaR)])) {
							setForegroundColorFromName(outlierColor2);
							run("Draw", "slice");
							outlierCounterNeg++;
						}
					}
					else if (values[i]<(meanMinusSDs[minOf(sIntervalsR-1,sigmaR)]) || values[i]>(meanPlusSDs[minOf(sIntervalsR-1,sigmaR)])) {
						if (values[i]>(meanPlusSDs[minOf(sIntervalsR-1,sigmaR)])){
							setForegroundColorFromName(outlierColor);
							run("Draw", "slice");
							outlierCounterPos++;
						}
						if (values[i]<(meanPlusSDs[minOf(sIntervalsR-1,sigmaR)])){
							setForegroundColorFromName(outlierColor2);
							run("Draw", "slice");
							outlierCounterNeg++;
						}
					}
				}
				else { outlierChoice = "No"; i = items;} /* there seems to be a coding malfunction */
			}
			run("Line Width...", "line=1"); /* Reset line width to ImageJ default */
			outlierCounter = outlierCounterPos + outlierCounterNeg;
		}
		else outlierCounter="No";
		// roiManager("show none");
		if (addLabels) {
			newImage("textImage", "8-bit black", imageWidth, imageHeight, 1);
			/*
			iterate through the ROI Manager list and draw scaled labels onto mask */
			fontArray = newArray(items);
			for (i=0; i<items; i++) {
				showStatus("Creating labels for object " + i + ", " + (roiManager("count")-i) + " more to go");
				roiManager("Select", i);
				labelString = d2s(values[i],decPlaces); /* Reduce decimal places for labeling (move these two lines to below the labels you prefer) */
				if(dpChoice=="Auto_Trimmed")	labelString = 	removeTrailingZerosAndPeriod	(labelString);
				Roi.getBounds(roiX, roiY, roiWidth, roiHeight);
				if (roiWidth>=roiHeight) roiMin = roiHeight;
				else roiMin = roiWidth;
				lFontS = fontSize; /* Initial estimate */
				setFont(fontName,lFontS,fontStyle);
				lFontS = fontSCorrection * fontSize * roiMin/(getStringWidth(labelString));
				if (lFontS>maxLFontS) lFontS = maxLFontS;
				if (lFontS<minLFontS) lFontS = minLFontS;
				if ((lFontS<10) && acceptMinFontSize) lFontS = 10;
				setFont(fontName,lFontS,fontStyle);
				if (ctrChoice=="ROI Center") {
					textOffset = roiX + ((roiWidth) - getStringWidth(labelString))/2;
					textDrop = roiY+roiHeight/2 + lFontS/2;
				} else {
					textOffset = getResult("mc_X\(px\)",i) - getStringWidth(labelString)/2;
					textDrop = getResult("mc_Y\(px\)",i) + lFontS/2;
				}
				/* Now make sure label is not out of the canvas */
				lFontFactor = lFontS/100;
				textOffset = maxOf(lFontFactor*shadowDisp,textOffset);
				textOffset = minOf(imageWidth-getStringWidth(labelString)-lFontFactor*shadowDisp,textOffset);
				textDrop = maxOf(0, textDrop);
				textDrop = minOf(imageHeight,textDrop);
				/* draw object label */
				setColor(255,255,255);
				drawString(labelString, textOffset, textDrop);
				fontArray[i] = lFontS;
			}
			Array.getStatistics(fontArray, minFontSize, null, meanFontSize, null);
			negAdj = 0.5;  /* negative offsets appear exaggerated at full displacement */
			if (shadowDrop<0) labelShadowDrop = round(shadowDrop * negAdj);
			else labelShadowDrop = shadowDrop;
			if (shadowDisp<0) labelShadowDisp = round(shadowDisp * negAdj);
			else labelShadowDisp = shadowDisp;
			if (shadowBlur<0) labelShadowBlur = round(shadowBlur *negAdj);
			else labelShadowBlur = shadowBlur;
			fontFactor = meanFontSize/100;
			minFontFactor = minFontSize/100;
			if (outlineStrokePC>0) objectOutlineStroke = maxOf(1,round(fontFactor * outlineStrokePC));
			else objectOutlineStroke = 0;
			if (shadowDrop>0) objectLabelShadowDrop = maxOf(1+objectOutlineStroke, floor(fontFactor * labelShadowDrop));
			else objectLabelShadowDrop = 0;
			if (shadowDisp>0) labelShadowDisp = maxOf(1+objectOutlineStroke, floor(fontFactor * labelShadowDisp));
			objectLabelShadowDisp = 0;
			if (shadowBlur>0) objectLabelShadowBlur = maxOf(objectOutlineStroke, floor(fontFactor * labelShadowBlur));
			else objectLabelShadowBlur = 0;
			run("Select None");
			roiManager("show none");
			fancyTextOverImage2(fontColor,outlineColor,objectLabelShadowDrop,objectLabelShadowDisp,objectLabelShadowBlur,shadowDarkness,objectOutlineStroke,innerTextEffect); /* requires "textImage" and original workingImage */
			closeImageByTitle("textImage");
			if (stroke>=0) workingImage = getTitle();
		}
		/*
			End of optional parameter label section
		*/
	}
	titleAbbrev = substring(tN, 0, minOf(15, lengthOf(tN))) + "...";
	/*
		Start of Optional Summary section
	*/
	if (summaryAdd) {
	/* Reduce decimal places - but not as much as ramp labels */
		summaryDP = decPlaces + 1;
		outlierChoiceAbbrev = cleanLabel(outlierChoice);
		if (outlierColor2==outlierColor){
			if (outlierChoice=="Manual_Input") 	outlierChoiceAbbrev = "<" + outlierMin + " >" + outlierMax + " " + unitLabel;
			else if (outlierChoice=="Ramp_Range") 	outlierChoiceAbbrev = "<" + rampMin + " >" + rampMax + " " + unitLabel;
			else outlierChoiceAbbrev = "<" + outlierChoiceAbbrev + ">";
		}
		else {
			if (outlierChoice=="Manual_Input") 	outlierChoiceAbbrevPos = "> " + outlierMax + " " + unitLabel;
			else if (outlierChoice=="Ramp_Range") 	outlierChoiceAbbrevPos = "> " + rampMax + " " + unitLabel;
			else outlierChoiceAbbrevPos = "> +" + outlierChoiceAbbrev;
			if (outlierChoice=="Manual_Input") 	outlierChoiceAbbrevNeg = "< " + outlierMin + " " + unitLabel;
			else if (outlierChoice=="Ramp_Range") 	outlierChoiceAbbrevNeg = "< " + rampMin + " " + unitLabel;
			else outlierChoiceAbbrevNeg = "< -" + outlierChoiceAbbrev;
		}
		arraySum =  d2s(arrayMean*items,summaryDP);
		arrayMean = d2s(arrayMean,summaryDP);
		coeffVar = d2s((100/arrayMean)*arraySD,summaryDP);
		arraySD = d2s(arraySD,summaryDP);
		arrayMin = d2s(arrayMin,summaryDP);
		arrayMax = d2s(arrayMax,summaryDP);
		median = d2s(arrayQuartile[1],summaryDP);
		if (IQR!=0) mode = d2s(mode,summaryDP);
		/* Then Statistics Summary Options Dialog . . . */
		Dialog.create("Statistics Summary Options");
			Dialog.addMessage("Summary output selected: " + summaryChoice);
			Dialog.addNumber("Change decimal places from " + summaryDP + ": ", summaryDP,0,2,"");
			defValLines = 6;
			statsChoice1 = newArray("Skip", "No More Stats", "Dashed Line:  ---", "Number of objects:  " + items);
			if (outlierChoice!="No"){
				if (outlierColor2==outlierColor) statsChoice2 = newArray("Outlines:  " + outlierCounter + " objects " + outlierChoiceAbbrev + " in " + outlierColor);
				else statsChoice2 = newArray("Outlines > :  " + outlierCounterPos + " objects " + outlierChoiceAbbrevPos + " in " + outlierColor,"Outlines < :  " + outlierCounterNeg + " objects " + outlierChoiceAbbrevNeg + " in " + outlierColor2);
			}
			statsChoice3 = newArray(
				"Mean:  " + arrayMean + " " + unitLabel,
				"Median:  " + median + " " + unitLabel,
				"StdDev:  " + arraySD + " " + unitLabel,
				"CoeffVar:  " + coeffVar + "%");
			statsChoice3a = newArray("Sum:  " + arraySum + " " + unitLabel);
			statsChoice3b = newArray("Min-Max:  " + arrayMin + " - " + arrayMax + " " +unitLabel);
			statsChoice3c = newArray("Minimum:  " + arrayMin + " " + unitLabel, "Maximum:  " + arrayMax + " " + unitLabel);
			if (indexOf(parameter,"Area")>=0){
				statsChoice3 = Array.concat(statsChoice3,statsChoice3a,statsChoice3b);
				defValLines++;
			}
			else statsChoice3 = Array.concat(statsChoice3,statsChoice3b, statsChoice3a);
			statsChoice4 = newArray(	/* additional frequency distribution stats */
				"Mode:  " + mode + " " + unitLabel + " \(W = " +autoDistW+ "\)",
				"InterQuartile Range:  " + IQR + " " + unitLabel);
			statsChoice5 = newArray();  /* log stats */
			eLMPS = expLnMeanPlusSDs.length;
			eLMMS = expLnMeanMinusSDs.length;
			statsChoice5 = Array.concat(statsChoice5,"ln Stats Mean:  " + d2s(expLnMeanPlusSDs[0],summaryDP) + " " +unitLabel);
			if (eLMPS>1)statsChoice5 = Array.concat(statsChoice5,"ln Stats +SD:  " + d2s((expLnMeanPlusSDs[1]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel);
			if (eLMPS>2) statsChoice5 = Array.concat(statsChoice5,"ln Stats +2SD:  " + d2s((expLnMeanPlusSDs[2]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel);
			if (eLMPS>3) statsChoice5 = Array.concat(statsChoice5,"ln Stats +3SD:  " + d2s((expLnMeanPlusSDs[3]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel);
			if (eLMMS>1) statsChoice5 = Array.concat(statsChoice5,"ln Stats -SD:  " + d2s((expLnMeanMinusSDs[1]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel);
			if (eLMMS>2) statsChoice5 = Array.concat(statsChoice5,"ln Stats -2SD:  " + d2s((expLnMeanMinusSDs[2]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel);
			if (eLMMS>3) statsChoice5 = Array.concat(statsChoice5,"ln Stats -3SD:  " + d2s((expLnMeanMinusSDs[3]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel);
			statsChoice6 = newArray("Pixel Size:  " + lcf + " " + unit, "Image Title:  " + titleAbbrev, "Manual",	"Long Underline:  ___","Blank line");
			if ((IQR!=0) && freqDistRamp) statsChoice3 = Array.concat(statsChoice3,statsChoice4,statsChoice3c);
			if (outlierChoice!="No") statsChoice = Array.concat(statsChoice1,statsChoice2,statsChoice3,statsChoice5,statsChoice6,statsChoice3c);
			else statsChoice = Array.concat(statsChoice1,statsChoice3,statsChoice5,statsChoice6,statsChoice3c);
			for (i=0; i<statsChoiceLines; i++) {
				if (i<10) Dialog.addChoice("Statistics label line "+(i+1)+":", statsChoice, statsChoice[i+2]);
				else Dialog.addChoice("Statistics label line "+(i+1)+":", statsChoice, statsChoice[0]);
			}
			if (menuLimit > 752)	textChoiceLines = 3;
			else textChoiceLines = 1;
			userInput = newArray(textChoiceLines);
			for (i=0; i<textChoiceLines; i++)
				Dialog.addString("Manual: Line selected above: "+(i+1)+":","None", 30);
		Dialog.show();
			newSummaryDP = Dialog.getNumber;
			statsLabLine = newArray(statsChoiceLines);
			for (i=0; i<statsChoiceLines; i++)
				statsLabLine[i] = Dialog.getChoice();
			textInputLines = newArray(textChoiceLines);
			for (i=0; i<textChoiceLines; i++)
				textInputLines[i] = Dialog.getString();
		if (newSummaryDP!=summaryDP) {
			summaryDP = newSummaryDP;
			arraySum = d2s(arrayMean*items,summaryDP);
			arrayMean = d2s(arrayMean,summaryDP);
			coeffVar = d2s((100/arrayMean)*arraySD,summaryDP);
			arraySD = d2s(arraySD,summaryDP);
			arrayMin = d2s(arrayMin,summaryDP);
			arrayMax = d2s(arrayMax,summaryDP);
			median = d2s(arrayQuartile[1],summaryDP);
			if (IQR!=0) mode = d2s(mode,summaryDP);
		}
	}
	sTextS = true;
	sTextC = "white";
	sTextCInv = "black";
	if (summaryToImage || paraLabAdd){
		if (bgI>=0){
			if (imageDepth==8 || imageDepth==24){
				if (bgI<5)	sTextC = "white";
				else if (bgI>250){
					sTextC = "black";
					sTextCInv = "white";
				}
				else sText = false;
			}if (imageDepth==16){
				if (bgI<(1285)) sTextC = "white";
				else if (bgI>64250){
					sTextC = "black";
					sTextCInv = "white";
				}
				else sText = false;
			}
		}
		Dialog.create("Parameter Label and Summary Formatting Options");
			if (paraLabAdd) {
				Dialog.addString("Parameter Label or Title:",paraLabelExp,3+minOf(32,lengthOf(paraLabelExp)));
				Dialog.addNumber("Parameter Label font size:", paraLabFontSize,1,4,"");
			}
			if (summaryToImage) Dialog.addNumber("Statistics text font size:", statsLabFontSize,1,4,"");
			if (sTextS){
				Dialog.addChoice("Summary and parameter font color:", colorChoices, sTextC);
				Dialog.addChoice("Summary and parameter outline color:", colorChoices, sTextCInv);
				Dialog.setInsets(2, 20, -10);
				Dialog.addMessage("Guessed background is " + bgI + ", suggesting simple " + sTextC + " summary text:",12,"#782F40");
				Dialog.setInsets(8, 20, 10);
				Dialog.addCheckbox("Override formatting with simple " + sTextC + " text, no outline or shadow", false);
			}
			else {
				iFontColorS = indexOfArray(colorChoices,call("ij.Prefs.qet", "fancyColorCoder.summaryFontColor",colorChoices[0]),0);
				Dialog.addChoice("Summary and parameter font color:", colorChoices, colorChoices[iFontColorS]);
				iOutlineColorS = indexOfArray(colorChoices,call("ij.Prefs.qet", "fancyColorCoder.summaryTextOutlineColor",colorChoices[1]),1);
				Dialog.addChoice("Summary and parameter outline color:", colorChoices, colorChoices[iOutlineColorS]);
			}
			if (menuLimit>=796) { /* room to show full dialog */
				Dialog.addNumber("Outline stroke:", outlineStrokePC,0,3,"% of summary font size");
				Dialog.addNumber("Shadow drop: ±", shadowDropPC,0,3,"% of summary font size");
				Dialog.addNumber("Shadow displacement Right: ±", shadowDropPC,0,3,"% of summary font size");
				Dialog.addNumber("Shadow Gaussian blur:", floor(0.75 * shadowDropPC),0,3,"% of summary font size");
				Dialog.addNumber("Shadow darkness \(darkest = 100\):",50,0,3,"%, neg.= glow");
			}
			else Dialog.addCheckbox("Tweak summary format?",false);
			fancyInnerEffectsChoices = newArray("None", "Recessed", "Raised");
			fancyInnerEffectsChoice = call("ij.Prefs.get", "fancyColorCoder.summaryTextInnerEffects","None");
			Dialog.addChoice("Inner text effects:",fancyInnerEffectsChoices,fancyInnerEffectsChoice);
		Dialog.show();
			if (paraLabAdd) {
				paraLabel = Dialog.getString();
				paraLabFontSize =  Dialog.getNumber();
			}
			if(summaryToImage) statsLabFontSize =  Dialog.getNumber();
			fontColorS = Dialog.getChoice();
			call("ij.Prefs.set", "fancyColorCoder.summaryFontColor",fontColorS);
			outlineColorS = Dialog.getChoice();
			call("ij.Prefs.set", "fancyColorCoder.summaryTextOutlineColor",outlineColorS);
			if (sTextS && !Dialog.getCheckbox()) sTextS = false;
			if (menuLimit>=796) {
				textLabelOutlineStrokePC = Dialog.getNumber();
				textLabelShadowDrop = Dialog.getNumber();
				textLabelShadowDisp = Dialog.getNumber();
				textLabelShadowBlur = Dialog.getNumber();
				textLabelShadowDarkness = Dialog.getNumber();
			}
			else if (Dialog.getCheckbox){
				Dialog.create("Statistics Summary Options Tweaks");
					Dialog.addNumber("Outline stroke:", outlineStrokePC,0,3,"% of stats label font size");
					Dialog.addNumber("Shadow drop: ±", shadowDropPC,0,3,"% of stats label font size");
					Dialog.addNumber("Shadow displacement Right: ±", shadowDropPC,0,3,"% of stats label font size");
					Dialog.addNumber("Shadow Gaussian blur:", floor(0.75 * shadowDropPC),0,3,"% of stats label font size");
					Dialog.addNumber("Shadow darkness \(darkest = 100\):",50,0,3,"%, neg.= glow");
				Dialog.show();
					textLabelOutlineStrokePC = Dialog.getNumber();
					textLabelShadowDrop = Dialog.getNumber();
					textLabelShadowDisp = Dialog.getNumber();
					textLabelShadowBlur = Dialog.getNumber();
					textLabelShadowDarkness = Dialog.getNumber();
			}
			else {
				textLabelOutlineStrokePC = outlineStrokePC;
				textLabelShadowDrop = shadowDropPC;
				textLabelShadowDisp = shadowDropPC;
				textLabelShadowBlur = floor(0.75 * shadowDropPC);
				textLabelShadowDarkness = 50;
			}
			summaryTextEffect = Dialog.getChoice();
			call("ij.Prefs.set", "fancyColorCoder.summaryTextInnerEffects",summaryTextEffect);
			fontFactor = statsLabFontSize/100;
			if (sTextS){
				fontColorS = sTextC;
				if (sTextC=="black") outlineColorS = "White";
				else outlineColorS = "Black";
				textLabelOutlineStroke = 0;
				textLabelOutlineStrokePC = 0;
				textLabelShadowDrop = 0;
				textLabelShadowDisp = 0;
				textLabelShadowBlur = 0;
				textLabelShadowDarkness = 0;
				paraOutlineStroke = 0;
				summaryTextEffect = "None";
			}
			else {
				/* End optional parameter label dialog */
				if (textLabelShadowDrop<0) textLabelShadowDrop = round(textLabelShadowDrop * negAdj);
				if (textLabelShadowDisp<0) textLabelShadowDisp = round(textLabelShadowDisp * negAdj);
				if (textLabelShadowBlur<0) textLabelShadowBlur = round(textLabelShadowBlur *negAdj);
				/* convert font percentages to pixels */
				textLabelOutlineStroke = round(fontFactor * textLabelOutlineStrokePC);
				textLabelShadowDrop = floor(fontFactor * textLabelShadowDrop);
				textLabelShadowDisp = floor(fontFactor * textLabelShadowDisp);
				textLabelShadowBlur = floor(fontFactor * textLabelShadowBlur);
				paraOutlineStroke = textLabelOutlineStroke * paraLabFontSize/minLFontS;
			}
		}
		/* End of on-image text drawing format options
		/*
		Count lines of summary label */
		if (paraLabAdd) labLines = 1;
		else labLines = 0;
		if(summaryAdd){
			statsLabLineText = newArray(statsChoiceLines);
			setFont(fontName, statsLabFontSize, fontStyle);
			if (lengthOf(t)>round(imageWidth/(1.5*fontSize)))
				titleShort = substring(t, 0, round(imageWidth/(1.5*fontSize))) + "...";
			else titleShort = t;
			for (i=0, j=0, statsLines=0, longestStringWidth=0, userTextLine=0; i<statsLabLineText.length; i++) {
				if (statsLabLine[i]!="None") {
					if (statsLabLine[i]=="No More Stats") i = statsLabLineText.length;
					else {
						statsLines = i + 1;
						if (indexOf(statsLabLine[i], ":  ")>0) statsLabLine[i] = substring(statsLabLine[i], 0, indexOf(statsLabLine[i], ":  "));
						if (startsWith(statsLabLine[i],"Dashed")) statsLabLineText[i] = "----------";
						else if (statsLabLine[i]=="Number of objects") statsLabLineText[j] = "Objects = " + items;
						else if (statsLabLine[i]=="Outlines") statsLabLineText[j] = "Outlines:  " + outlierCounter + " objects " + outlierChoiceAbbrev + " in " + replace(outlierColor,"_"," ");
						else if (statsLabLine[i]=="Outlines > ") statsLabLineText[j] = "Outlines > :  " + outlierCounterPos + " objects " + outlierChoiceAbbrevPos + " in " + replace(outlierColor,"_"," ");
						else if (statsLabLine[i]=="Outlines < ") statsLabLineText[j] = "Outlines < :  " + outlierCounterNeg + " objects " + outlierChoiceAbbrevNeg + " in " + replace(outlierColor2,"_"," ");
						else if (statsLabLine[i]=="Mean") statsLabLineText[j] = "Mean = " + arrayMean + " " + unitLabel;
						else if (statsLabLine[i]=="Median") statsLabLineText[j] = "Median = " + median + " " + unitLabel;
						else if (statsLabLine[i]=="StdDev") statsLabLineText[j] = "Std.Dev.: " + arraySD + " " + unitLabel;
						else if (statsLabLine[i]=="CoeffVar") statsLabLineText[j] = "Coeff.Var.: " + coeffVar + "%";
						else if (statsLabLine[i]=="Min-Max") statsLabLineText[j] = "Range: " + arrayMin + " - " + arrayMax + " " + unitLabel;
						else if (statsLabLine[i]=="Minimum") statsLabLineText[j] = "Minimum: " + arrayMin + " " + unitLabel;
						else if (statsLabLine[i]=="Maximum") statsLabLineText[j] = "Maximum: " + arrayMax + " " + unitLabel;
						else if (statsLabLine[i]=="Sum") statsLabLineText[j] = "Sum: " + arraySum + " " + unitLabel;
						else if (statsLabLine[i]=="Mode") statsLabLineText[j] = "Mode = " + mode + " " + unitLabel + " \(W = " +autoDistW+ "\)";
						else if (statsLabLine[i]=="InterQuartile Range") statsLabLineText[j] = "InterQuartile Range = " + IQR + " " +unitLabel;
						else if (statsLabLine[i]=="ln Stats Mean") statsLabLineText[j] = "ln Stats Mean: " + d2s(expLnMeanPlusSDs[0],summaryDP) + " " + unitLabel;
						else if (statsLabLine[i]=="ln Stats +SD") statsLabLineText[j] = "ln Stats +SD: " + d2s((expLnMeanPlusSDs[1]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
						else if (statsLabLine[i]=="ln Stats +2SD") statsLabLineText[j] = "ln Stats +2SD: " + d2s((expLnMeanPlusSDs[2]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
						else if (statsLabLine[i]=="ln Stats +3SD") statsLabLineText[j] = "ln Stats +3SD: " + d2s((expLnMeanPlusSDs[3]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
						else if (statsLabLine[i]=="ln Stats -SD") statsLabLineText[j] = "ln Stats -SD: " + d2s((expLnMeanMinusSDs[1]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
						else if (statsLabLine[i]=="ln Stats +2SD") statsLabLineText[j] = "ln Stats -2SD: " + d2s((expLnMeanMinusSDs[2]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
						else if (statsLabLine[i]=="ln Stats +3SD") statsLabLineText[j] = "ln Stats -3SD: " + d2s((expLnMeanMinusSDs[3]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
						else if (statsLabLine[i]=="Pixel Size") statsLabLineText[j] = "Scale: 1 pixel = " + lcf + " " + unit;
						else if (statsLabLine[i]=="Image Title") statsLabLineText[j] = "Image: " + titleShort;
						else if (statsLabLine[i]=="Manual"){
							 if (textInputLines[userTextLine]!="None") statsLabLineText[j] = textInputLines[userTextLine];
							 else statsLabLineText[j] = "";
							 userTextLine += 1;
						}
						else if (statsLabLine[i]=="Long Underline") statsLabLineText[j] = "__________";
						else if (statsLabLine[i]=="Blank Line") statsLabLineText[j] = " ";
						if (statsLabLine[i]!="Skip"){
							if (getStringWidth(statsLabLineText[j])>longestStringWidth) longestStringWidth = getStringWidth(statsLabLineText[j]);
							j++;
						}
					}
				}
			}
			linesSpace = 1.2 * ((labLines*paraLabFontSize)+(statsLines*statsLabFontSize));
		}
		if (paraLabAdd && !summaryAdd) longestStringWidth = getStringWidth(paraLabel);
		if (paraLabAdd || summaryToImage) {
			setFont(fontName,paraLabFontSize, fontStyle);
			just = "left"; /* set default justification */
			if (getStringWidth(paraLabel)>longestStringWidth) longestStringWidth = getStringWidth(paraLabel);
			if (paraLabPos == "Top Left") {
				posStartX = offsetX;
				posStartY = offsetY;
			} else if (paraLabPos == "Top Right") {
				posStartX = imageWidth - longestStringWidth - offsetX;
				posStartY = offsetY;
				just = "right";
			} else if (paraLabPos == "Center") {
				posStartX = round((imageWidth - longestStringWidth)/2);
				posStartY = round((imageHeight - linesSpace)/2);
				just = "center";
			} else if (paraLabPos == "Bottom Left") {
				posStartX = offsetX;
				posStartY = imageHeight - offsetY - linesSpace;
				just = "left";
			} else if (paraLabPos == "Bottom Right") {
				posStartX = imageWidth - longestStringWidth - offsetX;
				posStartY = imageHeight - offsetY - linesSpace;
				just = "right";
			} else if (paraLabPos == "At New Selection"){
				batchOn = is("Batch Mode");
				if (batchOn) setBatchMode("exit & display"); /* need to see what you are selecting */
				setTool("rectangle");
				msgtitle="Location for the summary labels...";
				msg = "Draw a box in the image where you want to center the summary labels...";
				waitForUser(msgtitle, msg);
				getSelectionBounds(selPosStartX, selPosStartY, posWidth, posHeight);
				run("Select None");
				posStartX = selPosStartX;
				posStartY = selPosStartY;
				if (batchOn) setBatchMode(true); /* Return to original batch mode setting */
			} else if (paraLabPos == "Current Selection"){
				posStartX = selPosStartX;
				posStartY = selPosStartY;
				posWidth = originalSelEWidth;
				posHeight = originalSelEHeight;
				if (selPosStartX<imageWidth*0.4) just = "left";
				else if (selPosStartX>imageWidth*0.6) just = "right";
				else just = "center";
			}
			if (endsWith(paraLabPos, "election")) {
				shrinkX = minOf(1,posWidth/longestStringWidth);
				shrinkY = minOf(1,posHeight/linesSpace);
				shrinkF = minOf(shrinkX, shrinkY);
				shrunkFont = shrinkF * paraLabFontSize;
				if (shrinkF < 1) {
					Dialog.create("Shrink Text");
						Dialog.addCheckbox("Text will not fit inside selection; Reduce font size from " + paraLabFontSize+ "?", true);
						Dialog.addNumber("Choose new font size; font size for fit =",round(shrunkFont));
					Dialog.show;
						reduceFontSize = Dialog.getCheckbox();
						shrunkFont = Dialog.getNumber();
					shrinkF = shrunkFont/paraLabFontSize;
				}
				else reduceFontSize = false;
				if (reduceFontSize == true) {
					paraLabFontSize = shrunkFont;
					statsLabFontSize = shrinkF * statsLabFontSize;
					linesSpace = shrinkF * linesSpace;
					longestStringWidth = shrinkF * longestStringWidth;
					fontFactor = statsLabFontSize/100;
					if (!sTextS){
						if (paraOutlineStroke>1) paraOutlineStroke = maxOf(1,round(fontFactor * paraOutlineStroke));
						else outlineStroke = round(fontFactor * paraOutlineStroke);
						if (textLabelShadowDrop>1) textLabelShadowDrop = maxOf(1,round(fontFactor * textLabelShadowDrop));
						else textLabelShadowDrop = round(fontFactor * textLabelShadowDrop);
						if (textLabelShadowDisp>1) textLabelShadowDisp = maxOf(1,round(fontFactor * textLabelShadowDisp));
						else textLabelShadowDisp = round(fontFactor * textLabelShadowDisp);
						if (textLabelShadowBlur>1) textLabelShadowBlur = maxOf(1,round(fontFactor * textLabelShadowBlur));
						else textLabelShadowBlur = round(fontFactor * textLabelShadowBlur);
					}
				}
				if (just=="auto") {
					if (posStartX<imageWidth*0.4) just = "left";
					else if (posStartX>imageWidth*0.6) just = "right";
					else just = "center";
				}
				if (just=="left") posStartX = posStartX + paraLabFontSize/2;
				else posStartX = posStartX + round((posWidth/2) - longestStringWidth/2);
				if (selPosStartY<imageHeight*0.4) posStartY = posStartY + paraLabFontSize/2;
				else posStartY = posStartY + round((posHeight/2) - (linesSpace/2) + fontSize);
			}
			run("Select None");
			if (posStartY<=1.5*paraLabFontSize)
				posStartY += paraLabFontSize;
			if (posStartX<offsetX) posStartX = offsetX;
			endX = posStartX + longestStringWidth;
			if ((endX+offsetX)>imageWidth) posStartX = imageWidth - longestStringWidth - offsetX;
			paraLabelX = posStartX;
			paraLabelY = posStartY;
			setColor(255,255,255);
		}
		else {
			paraLabelY = 1.5*fontSize;
			paraLabelX = 1.5*fontSize;
		}
		if (summaryToImage || paraLabAdd){
			/* Draw summary over top of object labels */
			if (is("Batch Mode")==false) setBatchMode(true);	/* toggle batch mode back on */
			textImages = newArray("textImage","antiAliased");
			/* Create Label Mask */
			newImage("textImage", "8-bit black", imageWidth, imageHeight, 1);
			roiManager("deselect");
			run("Select None");
			if (paraLabFontSize>=0) {
				setFont(fontName,paraLabFontSize, fontStyle);
				newImage("antiAliased", imageDepth, imageWidth, imageHeight, 1);
				/* Draw text for mask and antiAliased tweak */
				/* determine font color intensities settings for antialiased tweak */
				fontColorArray = getColorArrayFromColorName(fontColorS);
				Array.getStatistics(fontColorArray,fontIntMean);
				fontInt = floor(fontIntMean);
				outlineColorArray = getColorArrayFromColorName(outlineColorS);
				Array.getStatistics(outlineColorArray,outlineIntMean);
				outlineInt = floor(outlineIntMean);
				paraLabelY1 = paraLabelY;
				for (tImage=0; tImage<2; tImage++) {
					selectWindow(textImages[tImage]);
					if (tImage==0) setColor("white");
					else {
						paraLabelY = paraLabelY1;
						run("Select All");
						setColorFromColorName(outlineColorS);
						fill();
						roiManager("deselect");
						run("Select None");
						setColorFromColorName(fontColorS);
					}
					if (paraLabAdd) {
						setFont(fontName,paraLabFontSize, fontStyle);
						if (just=="left") drawString(paraLabel, paraLabelX, paraLabelY);
						else if (just=="right") drawString(paraLabel, paraLabelX + (longestStringWidth - getStringWidth(paraLabel)), paraLabelY);
						else drawString(paraLabel, paraLabelX + (longestStringWidth-getStringWidth(paraLabel))/2, paraLabelY);
						paraLabelY += round(1.2 * paraLabFontSize);
					}
					if (summaryToImage) {
						setFont(fontName,statsLabFontSize, fontStyle);
						for (iS=0; iS<statsLines; iS++) {
							if (statsLabLineText[iS]!="0" && statsLabLineText[iS]!=""){
								if (just=="left") drawString(statsLabLineText[iS], paraLabelX, paraLabelY);
								else if (just=="right") drawString(statsLabLineText[iS], paraLabelX + (longestStringWidth - getStringWidth(statsLabLineText[iS])), paraLabelY);
								else drawString(statsLabLineText[iS], paraLabelX + (longestStringWidth-getStringWidth(statsLabLineText[iS]))/2, paraLabelY);
								paraLabelY += round(1.2 * statsLabFontSize);
							}
						}
					}
				}
				fancyTextOverImage2(fontColorS,outlineColorS,textLabelShadowDrop,textLabelShadowDisp,textLabelShadowBlur,textLabelShadowDarkness,textLabelOutlineStroke,summaryTextEffect); /* requires "textImage" and original "workingImage" */
				/* function fancyTextOverImage@ requires shadowDrop,shadowDisp,shadowBlur,shadowDarkness,outlineStroke,text effect 
					Requires: functions: createShadowDropFromMask7Safe
				*/
				if (isOpen("antiAliased")) {
					imageCalculator("Max","textImage","antiAliased");
					imageCalculator("Min",workingImage,"textImage");
				}
				closeImageByTitle("textImage");
				closeImageByTitle("label_mask");
				closeImageByTitle("antiAliased");
			}
		}
	if(summaryToLog || summaryToFile){
		summaryText = "" + paraLabel + " summary for " + t;
		for (iS=0; iS<statsLines; iS++)
			if (statsLabLineText[iS]!="0" && statsLabLineText[iS]!="") summaryText += "\n" + statsLabLineText[iS];
		if (summaryToLog) IJ.log(summaryText);
		if (summaryToFile){
			summaryTextPath = tPath + tNL + parameter + "_summary.txt";
			File.saveString(summaryText,summaryTextPath);
		}
	}
/*
		End of Optional Summary section
*/
	if (stroke>=0) {
		run("Colors...", "foreground=black background=white selection=yellow"); /* reset colors */
		selectWindow(workingImage);
		if (countNaN!=0)
			print("\n>>>> ROI Color Coder:\n"
				+ "Some values from the \""+ parameter +"\" column could not be retrieved.\n"
				+ countNaN +" ROI(s) were labeled with a default color.");
		rename(tN + "_" + parameter + "\-coded");
		tNC = getTitle();
		/* Image and Ramp combination dialog */
		roiManager("Deselect");
		run("Select None");
		Dialog.create("Combine Labeled Image and Legend?");
			if (canvasH>imageHeight) comboChoice = newArray("No", "Combine Scaled Ramp with Current", "Combine Scaled Ramp with New Image", "Combine Scaled Ramp with New Manual Crop of Image");
			else if (canvasH>(0.93 * imageHeight)) comboChoice = newArray("No", "Combine Ramp with Current", "Combine Ramp with New Image", "Combine Scaled Ramp with New Manual Crop of Image", "Combine Scaled Ramp with New Auto Crop of Image"); /* 93% is close enough */
			else comboChoice = newArray("No", "Combine Scaled Ramp with Current", "Combine Scaled Ramp with New Image", "Combine Ramp with Current", "Combine Ramp with New Image", "Combine Scaled Ramp with New Manual Crop of Image", "Combine Scaled Ramp with New Auto Crop of Image");
			Dialog.addRadioButtonGroup("Combine Labeled Image and Legend?", comboChoice, 5, 1,  comboChoice[2]) ;
		Dialog.show();
			createCombo = Dialog.getRadioButton;
		if (createCombo!="No") {
			if (createCombo=="Combine Scaled Ramp with New Manual Crop of Image" || createCombo=="Combine Scaled Ramp with New Auto Crop of Image") {
				if (is("Batch Mode")==true) setBatchMode("exit & display");	/* toggle batch mode off */
				selectWindow(tNC);
				run("Duplicate...", "title=tempCrop");
				run("Select Bounding Box (guess background color)");
				run("Enlarge...", "enlarge=" + round(imageHeight*0.02) + " pixel"); /* Adds a 2% margin */
				if (createCombo=="Combine Scaled Ramp with New Manual Crop of Image") {
					setTool("rectangle");
					title="Crop Location for Combined Image";
					msg = "1. Select the area that you want to crop to. 2. Click on OK";
					waitForUser(title, msg);
				}
				if(selectionType>=0) run("Crop");
				else IJ.log("Combination with cropped image desired by no crop made");
				run("Select None");
				croppedImageHeight = getHeight(); croppedImageWidth = getWidth();
				if (is("Batch Mode")==false) setBatchMode(true);	/* toggle batch mode back on */
				selectWindow(tR);
				rampScale = croppedImageHeight/canvasH;
				run("Scale...", "x="+rampScale+" y="+rampScale+" interpolation=Bicubic average create title=scaled_ramp");
				canvasH = getHeight(); /* update ramp height */
				srW = getWidth + maxOf(2,croppedImageWidth/500);
				comboW = srW + croppedImageWidth + maxOf(2,croppedImageWidth/500);
				selectWindow("tempCrop");
				run("Canvas Size...", "width="+comboW+" height="+croppedImageHeight+" position=Top-Left");
				makeRectangle(croppedImageWidth + maxOf(2,croppedImageWidth/500), round((croppedImageHeight-canvasH)/2), srW, croppedImageHeight);
				setBatchMode("exit & display");
				selectWindow("tempCrop"); /* voodoo step seems to help  . . . */
				wait(10); /* required to get image to selection to work here */
				run("Image to Selection...", "image=scaled_ramp opacity=100");
				run("Flatten");
				if (imageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
				rename(tNC + "_crop+ramp");
				closeImageByTitle("scaled_ramp");
				closeImageByTitle("temp_combo");
				closeImageByTitle("tempCrop");
			}
			else {
				if (!isOpen(tR)) {
						openImages = getList("image.titles");
						iRamp = -1;
						for (i=0; i<openImages.length; i++) if (endsWith(openImages[i],"Ramp")>=0) iRamp = i;
						if (iRamp>=0){
							IJ.log("Expected ramp image\n" + tR + "\nwas not found and was replaced by\n" + openImages[iRamp]);
							tR = openImages[iRamp];
						} 
						else exit ("Ramp image " + tR + " not found");
				}
				selectWindow(tR);
				// while(indexOf(tR," ")>=0) replace(tR," ","_");
				// rename(tR);
				if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Scaled Ramp with New Image") {
					rampScale = imageHeight/canvasH;
					run("Scale...", "x="+rampScale+" y="+rampScale+" interpolation=Bicubic average create title=scaled_ramp");
					canvasH = getHeight(); /* update ramp height */
				}
				srW = getWidth + maxOf(2,imageWidth/500);
				comboW = srW + imageWidth + maxOf(2,imageWidth/500);
				selectWindow(tNC);
				if (createCombo=="Combine Scaled Ramp with New Image" || createCombo=="Combine Ramp with New Image") run("Duplicate...", "title=temp_combo");
				run("Canvas Size...", "width="+comboW+" height="+imageHeight+" position=Top-Left");
				makeRectangle(imageWidth + maxOf(2,imageWidth/500), round((imageHeight-canvasH)/2), srW, imageHeight);
				setBatchMode("exit & display");
				if (createCombo=="Combine Scaled Ramp with New Image"){
					selectWindow("temp_combo"); /* voodoo step seems to help  . . . */
					wait(10); /* required to get image to selection to work here */
					run("Image to Selection...", "image=scaled_ramp opacity=100");
				}
				else if (createCombo=="Combine Scaled Ramp with Current"){
					selectWindow(tNC); /* voodoo step seems to help  . . . */
					wait(10); /* required to get image to selection to work here */
					run("Image to Selection...", "image=scaled_ramp opacity=100");
				}
				else run("Image to Selection...", "image="+tR+" opacity=100"); /* can use "else" here because we have already eliminated the "No" option */
				run("Flatten");
				if (imageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
				rename(tNC + "+ramp");
				closeImageByTitle("scaled_ramp");
				closeImageByTitle("temp_combo");
				if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Ramp with Current") closeImageByTitle(tNC);
			}
		}
	}
	if (selectionExists){
		/* Restore original selection to original image */
		finalID = getImageID();
		selectImage(orID);
		makeRectangle(selPosStartX, selPosStartY, originalSelEWidth, originalSelEHeight);
		selectImage(finalID);
	}
	setBatchMode("exit & display");
	restoreSettings;
	memFlush(200);
	showStatus(macroL + " macro finished");
	beep(); wait(300); beep(); wait(300); beep();
	/* End of ROI Color Coder with Scaled Labels and Summary */
}
	/*
		   ( 8(|)	( 8(|)	Functions	@@@@@:-)	@@@@@:-)
   */
	function AddMCsToResultsTable() {
	/* 	Based on "MCentroids.txt" Morphological centroids by thinning assumes white particles: G. Landini
		https://imagej.net/doku.php?id=plugin:morphology:morphological_operators_for_imagej:start
		http://www.mecourse.com/landinig/software/software.html
		Modified to add coordinates to Results Table: Peter J. Lee NHMFL  7/20-29/2016
		v180102	Fixed typos and updated functions.
		v180104 Removed unnecessary changes to settings.
		v180312 Add minimum and maximum morphological radii.
		v180602 Add 0.5 pixels to output co-ordinates to match X,Y, XM and YM system for ImageJ results
		v190802 Updated distance measurement to use more compact pow function.
		v220707 Uses toWhiteBGBinary instead of binary[-]Check. Use duplicate image to retain color.
	*/
		workingTitle = getTitle();
		if (!checkForPlugin("morphology_collection")) restoreExit("Exiting: Gabriel Landini's morphology suite is needed to run this function.");
		toWhiteBGBinary(workingTitle); /* Makes sure image is binary and sets to white background, black objects */
		checkForRoiManager(); /* This macro uses ROIs and a Results table that matches in count */
		roiOriginalCount = roiManager("count");
		addRadii = getBoolean("Do you also want to add the min and max M-Centroid radii to the Results table?");
		batchMode = is("Batch Mode"); /* Store batch status mode before toggling */
		if (!batchMode) setBatchMode(true); /* Toggle batch mode on if previously off */
		start = getTime();
		getPixelSize(unit, pixelWidth, pixelHeight);
		lcf=(pixelWidth+pixelHeight)/2;
		objects = roiManager("count");
		mcImageWidth = getWidth();
		mcImageHeight = getHeight();
		showStatus("Looping through all " + roiOriginalCount + " objects for morphological centers . . .");
		for (i=0 ; i<roiOriginalCount; i++) {
			showProgress(-i, roiManager("count"));
			selectWindow(workingTitle);
			roiManager("select", i);
			if(addRadii) run("Interpolate", "interval=1");	getSelectionCoordinates(xPoints, yPoints); /* place border coordinates in array for radius measurements - Wayne Rasband: http://imagej.1557.x6.nabble.com/List-all-pixel-coordinates-in-ROI-td3705127.html */
			Roi.getBounds(Rx, Ry, Rwidth, Rheight);
			setResult("ROIctr_X\(px\)", i, Rx + Rwidth/2);
			setResult("ROIctr_Y\(px\)", i, Ry + Rheight/2);
			Roi.getContainedPoints(RPx, RPy); /* This includes holes when ROIs are used, so no hole filling is needed */
			newImage("Contained Points","8-bit black",Rwidth,Rheight,1); /* Give each sub-image a unique name for debugging purposes */
			for (j=0; j<lengthOf(RPx); j++)
				setPixel(RPx[j]-Rx, RPy[j]-Ry, 255);
			selectWindow("Contained Points");
			run("BinaryThin2 ", "kernel_a='0 2 2 0 1 1 0 0 2 ' kernel_b='0 0 2 0 1 1 0 2 2 ' rotations='rotate 45' iterations=-1 white");
			for (j=0; j<lengthOf(RPx); j++){
				if((getPixel(RPx[j]-Rx, RPy[j]-Ry))==255) {
					centroidX = RPx[j]; centroidY = RPy[j];
					setResult("mc_X\(px\)", i, centroidX + 0.5); /* Add 0.5 pixel to correct pixel coordinates to center of pixel */
					setResult("mc_Y\(px\)", i, centroidY + 0.5);
					setResult("mc_offsetX\(px\)", i, getResult("X",i)/lcf-(centroidX + 0.5));
					setResult("mc_offsetY\(px\)", i, getResult("Y",i)/lcf-(centroidY + 0.5));
					j = lengthOf(RPx); /* one point and done */
				}
			}
			closeImageByTitle("Contained Points");
			if(addRadii) {
				/* Now measure min and max radii from M-Centroid */
				rMin = Rwidth + Rheight; rMax = 0;
				for (j=0 ; j<(lengthOf(xPoints)); j++) {
					dist = sqrt(pow(centroidX-xPoints[j],2)+pow(centroidY-yPoints[j],2));
					if (dist < rMin) { rMin = dist; rMinX = xPoints[j]; rMinY = yPoints[j];}
					if (dist > rMax) { rMax = dist; rMaxX = xPoints[j]; rMaxY = yPoints[j];}
				}
				if (rMin == 0) rMin = 0.5; /* Correct for 1 pixel width objects and interpolate error */
				setResult("mc_minRadX", i, rMinX + 0.5); /* Add 0.5 pixel to correct pixel coordinates to center of pixel */
				setResult("mc_minRadY", i, rMinY + 0.5);
				setResult("mc_maxRadX", i, rMaxX + 0.5);
				setResult("mc_maxRadY", i, rMaxY + 0.5);
				setResult("mc_minRad\(px\)", i, rMin);
				setResult("mc_maxRad\(px\)", i, rMax);
				setResult("mc_AR", i, rMax/rMin);
				if (lcf!=1) {
					setResult('mc_minRad' + "\(" + unit + "\)", i, rMin*lcf);
					setResult('mc_maxRad' + "\(" + unit + "\)", i, rMax*lcf);
				}
			}
		}
		updateResults();
		run("Select None");
		if (!batchMode) setBatchMode(false); /* Toggle batch mode off */
		showStatus("MC Function Finished: " + roiManager("count") + " objects analyzed in " + (getTime()-start)/1000 + "s.");
		beep(); wait(300); beep(); wait(300); beep();
		call("java.lang.System.gc");
	}
 	function autoCalculateDecPlaces3(min,max,intervals){
		/* v210428 3 variable version */
		step = (max-min)/intervals;
		stepSci = d2s(step, -1);
		iExp = indexOf(stepSci, "E");
		stepExp = parseInt(substring(stepSci, iExp+1));
		if (stepExp<-7) dP = -1; /* Scientific Notation */
		else if (stepExp<0) dP = -1*stepExp+1;
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
		if (getDirectory("plugins") == "") print("Failure to find any plugins!");
		else {
			pluginDir = getDirectory("plugins");
			if (lastIndexOf(pluginName,".")==pluginName.length-1) pluginName = substring(pluginName,0,pluginName.length-1);
			pExts = newArray(".jar",".class");
			knownExt = false;
			for (j=0; j<lengthOf(pExts); j++) if(endsWith(pluginName,pExts[j])) knownExt = true;
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
					for (i=0,subFolderCount=0; i<lengthOf(pluginList); i++) {
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
			v181005 1st version that works correctly ?
			v210429 Updates for expandable arrays
			v220510 Fixed subfolder error
			NOTE: requires ASC restoreExit function which requires previous run of saveSettings
			NOTE: underlines are NOT converted to spaces in names */
		var pluginCheck = false;
		if (getDirectory("plugins") == "") restoreExit("Failure to find any plugins!");
		else pluginDir = getDirectory("plugins");
		pluginList = getFileList(pluginDir);
		/* First check root plugin folder */
		for (i=0; i<lengthOf(pluginList); i++) {
			if (!endsWith(pluginList[i], "/") && endsWith(pluginList[i], ".jar")) {
				if (indexOf(pluginList[i], pluginNamePart)>=0) {
					pluginCheck = true;
					i=lengthOf(pluginList);
				}
			}
		}
		/* If not in the root try the subfolders */
		if (!pluginCheck) {
			subFolderList = newArray();
			for (i=0,countSF=0; i<lengthOf(pluginList); i++) {
				if (endsWith(pluginList[i], "/")){
					subFolderList[countSF] = pluginList[i];
					countSF++;
				}
			}
			for (i=0; i<countSF; i++) {
				subFolderPluginList = getFileList(pluginDir + subFolderList[i]);
				for (j=0; j<lengthOf(subFolderPluginList); j++) {
					if (endsWith(subFolderPluginList[j], ".jar") || endsWith(subFolderPluginList[j], ".class")) {
						if (indexOf(subFolderPluginList[j], pluginNamePart)>=0) {
							pluginCheck = true;
							i=lengthOf(subFolderList);
							j=lengthOf(subFolderPluginList);
						}
					}
				}
			}
		}
		return pluginCheck;
	}
	function checkForResults() {
		/* v220706 More friendly to Results tables not called "Results" */
		nROIs = roiManager("count");
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
			Dialog.addMessage("This macro requires a Results table to analyze.\n \nThere are " + nRes +" results.\nThere are " + nROIs +" ROIs.");
			Dialog.addRadioButtonGroup("No Results to Work With:",newArray("Run Analyze-particles to generate table","Import Results table","Exit"),2,1,"Run Analyze-particles to generate table");
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
			v220816: Enforces non-inverted LUT as well as white background and fixes ROI-less analyze. Adds more dialog labeling.
			v220823: Extended corner pixel test.
			*/
		functionL = "checkForRoiManager_v220816";
		nROIs = roiManager("count");
		nRes = nResults;
		tSize = Table.size;
		if (nRes==0 && tSize>0){
			oTableTitle = Table.title;
			renameTable = getBoolean("There is no Results table but " + oTableTitle + "has " +tSize+ "rows:", "Rename to Results", "No, I will take may chances");
			if (renameTable) {
				Table.rename(oTableTitle, "Results");
				nRes = nResults;
			}
		}
		if(nROIs==0 || nROIs!=nRes){
			Dialog.create("ROI mismatch options: " + functionL);
				Dialog.addMessage("This macro requires that all objects have been loaded into the ROI manager.\n \nThere are   " + nRes +"   results.\nThere are   " + nROIs +"   ROIs.\nDo you want to:");
				mismatchOptions = newArray();
				if(nROIs==0) mismatchOptions = Array.concat(mismatchOptions,"Import a saved ROI list");
				else mismatchOptions = Array.concat(mismatchOptions,"Replace the current ROI list with a saved ROI list");
				if(nRes==0) mismatchOptions = Array.concat(mismatchOptions,"Import a Results Table \(csv\) file");
				else mismatchOptions = Array.concat(mismatchOptions,"Clear Results Table and import saved csv");
				mismatchOptions = Array.concat(mismatchOptions,"Clear ROI list and Results Table and reanalyze \(overrides above selections\)");
				if (!is("binary")) Dialog.addMessage("The active image is not binary, so it may require thresholding before analysis");
				mismatchOptions = Array.concat(mismatchOptions,"Get me out of here, I am having second thoughts . . .");
				Dialog.addRadioButtonGroup("ROI mismatch; what would you like to do:_____", mismatchOptions, lengthOf(mismatchOptions), 1, mismatchOptions[0]);
			Dialog.show();
				mOption = Dialog.getRadioButton();
				if (startsWith(mOption,"Sorry")) restoreExit("Sorry this did not work out for you.");
			if (startsWith(mOption,"Clear ROI list and Results Table and reanalyze")) {
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
						getThreshold(t1,t2);
						if (t1==-1)  {
							run("Auto Threshold", "method=Default");
							setOption("BlackBackground", false);
							run("Make Binary");
						}
					}
				}
				if (is("Inverting LUT"))  run("Invert LUT");
				/* Make sure black objects on white background for consistency */
				if (bitDepth()!=24){
					yMax = Image.height-1;	xMax = Image.width-1;
					cornerPixels = newArray(getPixel(0,0),getPixel(1,1),getPixel(0,yMax),getPixel(xMax,0),getPixel(xMax,yMax),getPixel(xMax-1,yMax-1));
					Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
					if (cornerMax!=cornerMin){
						actionOptions = newArray("Remove black edge objects","Invert, then remove black edge objects","Exit","Feeling lucky");
						Dialog.create("Border pixel inconsistency");
							Dialog.addMessage("cornerMax="+cornerMax+ " but cornerMin=" +cornerMin+ " and cornerMean = "+cornerMean+" problem with image border");
							Dialog.addRadioButtonGroup("Actions:",actionOptions,actionOptions.length,1,"Remove black edge objects");
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
				if (isOpen("ROI Manager"))	roiManager("reset");
				setOption("BlackBackground", false);
				if (isOpen("Results")) {
					selectWindow("Results");
					run("Close");
				}
				// run("Analyze Particles..."); /* Letting users select settings does not create ROIs  ¯\_(?)_/¯ */
				run("Analyze Particles...", "display clear include add");
				nROIs = roiManager("count");
				nRes = nResults;
				if (nResults!=roiManager("count"))
					restoreExit(functionL + ": Results \(" +nRes+ "\) and ROI Manager \(" +nROIs+ "\) counts still do not match!");
			}
			else {
				if (startsWith(mOption,"Import a saved ROI")) {
					if (isOpen("ROI Manager"))	roiManager("reset");
					msg = functionL + ": Import ROI set \(zip file\), click \"OK\" to continue to file chooser";
					showMessage(msg);
					pathROI = File.openDialog(functionL + ": Select an ROI file set to import");
                    roiManager("open", pathROI);
				}
				if (startsWith(mOption,"Import a Results")){
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
		nRes = nResults; /* Used to check for ROIs:Results mismatch */
		if(nROIs==0 || nROIs!=nRes)
			restoreExit(functionL + ": Goodbye, there are " + nROIs + " ROIs and " + nRes + " results; your previous settings will be restored.");
		return roiManager("count"); /* Returns the new count of entries */
	}
	function checkForUnits() {  /* Generic version
		/* v161108 (adds inches to possible reasons for checking calibration)
		 v170914 Radio dialog with more information displayed
		 v200925 looks for pixels unit too; v210428 just adds function label */
		functionL = "checkForUnits_v210428";
		getPixelSize(unit, pixelWidth, pixelHeight);
		if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="" || unit=="inches" || unit=="pixels"){
			Dialog.create("Suspicious Units: " + functionL);
			rescaleChoices = newArray("Define new units for this image", "Use current scale", "Exit this macro");
			rescaleDialogLabel = "pixelHeight = "+pixelHeight+", pixelWidth = "+pixelWidth+", unit = "+unit+": what would you like to do?";
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
		v200604	fromCharCode(0x207B) removed as superscript hyphen not working reliably	*/
		string= replace(string, "\\^2", fromCharCode(178)); /* superscript 2 */
		string= replace(string, "\\^3", fromCharCode(179)); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, "\\^-"+ fromCharCode(185), "-" + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-"+ fromCharCode(178), "-" + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "\\^-^1", "-" + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-^2", "-" + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "\\^-1", "-" + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-2", "-" + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "\\^-^1", "-" + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-^2", "-" + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "(?<![A-Za-z0-9])u(?=m)", fromCharCode(181)); /* micron units */
		string= replace(string, "\\b[aA]ngstrom\\b", fromCharCode(197)); /* Ångström unit symbol */
		string= replace(string, "  ", " "); /* Replace double spaces with single spaces */
		string= replace(string, "_", " "); /* Replace underlines with space as thin spaces (fromCharCode(0x2009)) not working reliably  */
		string= replace(string, "px", "pixels"); /* Expand pixel abbreviation */
		string= replace(string, "degreeC", fromCharCode(0x00B0) + "C"); /* Degree symbol for dialog boxes */
		string = replace(string, " " + fromCharCode(0x00B0), fromCharCode(0x2009) + fromCharCode(0x00B0)); /* Replace normal space before degree symbol with thin space */
		string= replace(string, " °", fromCharCode(0x2009) + fromCharCode(0x00B0)); /* Replace normal space before degree symbol with thin space */
		string= replace(string, "sigma", fromCharCode(0x03C3)); /* sigma for tight spaces */
		string= replace(string, "±", fromCharCode(0x00B1)); /* plus or minus */
		return string;
	}
	function closeImageByTitle(windowTitle) {  /* Cannot be used with tables */
		/* v181002 reselects original image at end if open
		   v200925 uses "while" instead of "if" so that it can also remove duplicates
		*/
		oIID = getImageID();
        while (isOpen(windowTitle)) {
			selectWindow(windowTitle);
			close();
		}
		if (isOpen(oIID)) selectImage(oIID);
	}
	function createConvolverMatrix(effect,thickness){
		/* v230413: 1st version PJL  Effects assumed: "Recessed or Raised" */
		matrixText = "";
		matrixSize = maxOf(3,(1 + 2*round(thickness/10)));
		matrixLC = matrixSize -1;
		matrixCi = matrixSize/2 - 0.5;
		mFact = 1/(matrixSize-1);
		for(y=0,c=0;y<matrixSize;y++){
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
		if (oStroke>0) run("Enlarge...", "enlarge="+oStroke+" pixel"); /* Adjust shadow size so that shadow extends beyond stroke thickness */
		run("Clear");
		run("Select None");
		if (oShadowBlur>0) {
			run("Gaussian Blur...", "sigma="+oShadowBlur);
			run("Unsharp Mask...", "radius="+oShadowBlur+" mask=0.4"); /* Make Gaussian shadow edge a little less fuzzy */
		}
		/* Now make sure shadow or glow does not impact outline */
		getSelectionFromMask(mask);
		if (oStroke>0) run("Enlarge...", "enlarge="+oStroke+" pixel");
		Color.setBackground("black");
		run("Clear");
		run("Select None");
		/* The following are needed for different bit depths */
		if (imageDepth==16 || imageDepth==32) run(imageDepth + "-bit");
		run("Enhance Contrast...", "saturated=0 normalize");
		divider = (100 / abs(oShadowDarkness));
		run("Divide...", "value="+divider);
		Color.setBackground(orBG);
	}
	function expandLabel(str) {  /* Expands abbreviations typically used for compact column titles
		v200604	fromCharCode(0x207B) removed as superscript hyphen not working reliably
		v211102-v211103  Some more fixes and updated to match latest extended geometries
		v220808 replaces ° with fromCharCode(0x00B0)
		v230106 Added a few separation abbreviations
		v230109 Reorganized to priortize all standard IJ labels and make more consistent. Also introduced string.replace and string.substring */
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
		else { /* additional ASC geomotries */
			str = str.replace(fromCharCode(0x00B0), "degrees");
			str = str.replace("0-90_degrees", "0-90"+fromCharCode(0x00B0)); /* An exception to the above*/
			str = str.replace("0-90degrees", "0-90"+fromCharCode(0x00B0)); /* An exception to the above*/
			str = str.replace("_cAR", "\(Corrected by Aspect Ratio\) ");
			str = str.replace("AR_", "Aspect Ratio: ");
			str = str.replace("BoxH","Bounding Rectangle Height ");
			str = str.replace("BoxW","Bounding Rectangle Width ");
			str = str.replace("Cir_to_El_Tilt", "Circle Tilt \(tilt of curcle to match measured ellipse\) ");
			str = str.replace(" Crl ", " Curl ");
			str = str.replace("Compact_Feret", "Compactness \(from Feret axis\) ");
			str = str.replace("Da_Equiv","Diameter \(from circle area\) ");
			str = str.replace("Dp_Equiv","Diameter \(from circle perimeter\) ");
			str = str.replace("Dsph_Equiv","Diameter \(from spherical Feret diameter\) ");
			str = str.replace("Da", "Diameter \(from circle area\) ");
			str = str.replace("Dp", "Diameter \(from circle perimeter\) ");
			str = str.replace("equiv", "Equivalent ");
			str = str.replace("FeretAngle", "Feret's Angle ");
			str = str.replace("Feret's Angle 0to90", "Feret's Angle \(0-90"+fromCharCode(0x00B0)+"\)"); /* fixes a precious labelling inconsistency */
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
			if (indexOf(str,"Perimeter")!=indexOf(str,"Perim")) str.replace("Perim", "Perimeter ");
			str = str.replace("Perimetereter", "Perimeter "); /* just in case above failed */
			str = str.replace("Snk", "\(Snake\) ");
			str = str.replace("Raw Int Den", "Raw Interfacial Density ");
			str = str.replace("Rndnss", "Roundness ");
			str = str.replace("Rnd_", "Roundness: ");
			str = str.replace("Rss1", "/(Russ Formula 1/) ");
			str = str.replace("Rss1", "/(Russ Formula 2/) ");
			str = str.replace("Sqr_", "Square: ");
			str = str.replace("Squarity_AP","Squarity \(from area and perimeter\) ");
			str = str.replace("Squarity_AF","Squarity \(from area and Feret\) ");
			str = str.replace("Squarity_Ff","Squarity \(from Feret\) ");
			str = str.replace(" Th ", " Thickness ");
			str = str.replace("ThisROI"," this ROI ");
			str = str.replace("Vol_", "Volume: ");
			if(str=="Width") str = "Bounding Rectangle Width";
			str = str.replace("XM", "Center of Mass \(x\)");
			str = str.replace("XY", "Center of Mass \(y\)");
			str = str.replace(fromCharCode(0x00C2), ""); /* Remove mystery Â */
			// str = str.replace("^-", fromCharCode(0x207B)); /* Replace ^- with superscript - Not reliable though */
			str = str.replace(fromCharCode(0x2009)," ");
		}
		while (indexOf(str,"_")>=0) str = str.replace("_", " ");
		while (indexOf(str,"  ")>=0) str = str.replace("  ", " ");
		while (endsWith(str," ")) str = str.substring(0,lengthOf(str)-1);
		return str;
	}
	function fancyTextOverImage2(fontColor,outlineColor,shadowDrop,shadowDisp,shadowBlur,shadowDarkness,outlineStroke,effect) { /* Place text over image in a way that stands out; requires original "workingImage" and "textImage"
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
			imageCalculator("Subtract",workingImage,"shadow");
		if (isOpen("shadow") && (shadowDarkness<0))	/* Glow */
			imageCalculator("Add",workingImage,"shadow");
		run("Select None");
		/* Create outline around text */
		getSelectionFromMask("label_mask");
		getSelectionBounds(maskX, maskY, null, null);
		outlineStrokeOffset = maxOf(0,(outlineStroke/2)-1);
		setSelectionLocation(maskX+outlineStrokeOffset, maskY+outlineStrokeOffset); /* Offset selection to create shadow effect */
		run("Enlarge...", "enlarge="+outlineStroke+" pixel");
		setBackgroundFromColorName(outlineColor);
		run("Clear", "slice");
		run("Enlarge...", "enlarge="+outlineStrokeOffset+" pixel");
		run("Gaussian Blur...", "sigma="+outlineStrokeOffset);
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
			run("Convolve...", "text1=[ " + createConvolverMatrix(effect,fontLineWidth) + " ]");
			if (rAlpha>0.33) run("Gaussian Blur...", "sigma="+rAlpha);
			run("Select None");
		}
		/* The following steps smooth the interior of the text labels */
		selectWindow("textImage");
		getSelectionFromMask("label_mask");
		run("Make Inverse");
		run("Invert");
		run("Select None");
		imageCalculator("Min",workingImage,"textImage");
		closeImageByTitle("shadow");
		closeImageByTitle("inner_shadow");
		closeImageByTitle("label_mask");
	}
/*
	 Macro Color Functions
 */
	function getColorArrayFromColorName(colorName) {
		/* v180828 added Fluorescent Colors
		   v181017-8 added off-white and off-black for use in gif transparency and also added safe exit if no color match found
		   v191211 added Cyan
		   v211022 all names lower-case, all spaces to underscores v220225 Added more hash value comments as a reference v220706 restores missing magenta
		   REQUIRES restoreExit function.  57 Colors v230130 Added more descriptions and modified order
		*/
		if (colorName == "white") cA = newArray(255,255,255);
		else if (colorName == "black") cA = newArray(0,0,0);
		else if (colorName == "off-white") cA = newArray(245,245,245);
		else if (colorName == "off-black") cA = newArray(10,10,10);
		else if (colorName == "light_gray") cA = newArray(200,200,200);
		else if (colorName == "gray") cA = newArray(127,127,127);
		else if (colorName == "dark_gray") cA = newArray(51,51,51);
		else if (colorName == "off-black") cA = newArray(10,10,10);
		else if (colorName == "light_gray") cA = newArray(200,200,200);
		else if (colorName == "gray") cA = newArray(127,127,127);
		else if (colorName == "dark_gray") cA = newArray(51,51,51);
		else if (colorName == "red") cA = newArray(255,0,0);
		else if (colorName == "green") cA = newArray(0,255,0); /* #00FF00 AKA Lime green */
		else if (colorName == "blue") cA = newArray(0,0,255);
		else if (colorName == "cyan") cA = newArray(0, 255, 255);
		else if (colorName == "yellow") cA = newArray(255,255,0);
		else if (colorName == "magenta") cA = newArray(255,0,255); /* #FF00FF */
		else if (colorName == "pink") cA = newArray(255, 192, 203);
		else if (colorName == "violet") cA = newArray(127,0,255);
		else if (colorName == "orange") cA = newArray(255, 165, 0);
		else if (colorName == "garnet") cA = newArray(120,47,64); /* #782F40 */
		else if (colorName == "gold") cA = newArray(206,184,136); /* #CEB888 */
		else if (colorName == "aqua_modern") cA = newArray(75,172,198); /* #4bacc6 AKA "Viking" aqua */
		else if (colorName == "blue_accent_modern") cA = newArray(79,129,189); /* #4f81bd */
		else if (colorName == "blue_dark_modern") cA = newArray(31,73,125); /* #1F497D */
		else if (colorName == "blue_honolulu") cA = newArray(0,118,182); /* Honolulu Blue #30076B6 */
		else if (colorName == "blue_modern") cA = newArray(58,93,174); /* #3a5dae */
		else if (colorName == "gray_modern") cA = newArray(83,86,90); /* bright gray #53565A */
		else if (colorName == "green_dark_modern") cA = newArray(121,133,65); /* Wasabi #798541 */
		else if (colorName == "green_modern") cA = newArray(155,187,89); /* #9bbb59 AKA "Chelsea Cucumber" */
		else if (colorName == "green_modern_accent") cA = newArray(214,228,187); /* #D6E4BB AKA "Gin" */
		else if (colorName == "green_spring_accent") cA = newArray(0,255,102); /* #00FF66 AKA "Spring Green" */
		else if (colorName == "orange_modern") cA = newArray(247,150,70); /* #f79646 tan hide, light orange */
		else if (colorName == "pink_modern") cA = newArray(255,105,180); /* hot pink #ff69b4 */
		else if (colorName == "purple_modern") cA = newArray(128,100,162); /* blue-magenta, purple paradise #8064A2 */
		else if (colorName == "jazzberry_jam") cA = newArray(165,11,94);
		else if (colorName == "red_n_modern") cA = newArray(227,24,55);
		else if (colorName == "red_modern") cA = newArray(192,80,77);
		else if (colorName == "tan_modern") cA = newArray(238,236,225);
		else if (colorName == "violet_modern") cA = newArray(76,65,132);
		else if (colorName == "yellow_modern") cA = newArray(247,238,69);
		/* Fluorescent Colors https://www.w3schools.com/colors/colors_crayola.asp */
		else if (colorName == "radical_red") cA = newArray(255,53,94);			/* #FF355E */
		else if (colorName == "wild_watermelon") cA = newArray(253,91,120);		/* #FD5B78 */
		else if (colorName == "shocking_pink") cA = newArray(255,110,255);		/* #FF6EFF Ultra Pink */
		else if (colorName == "razzle_dazzle_rose") cA = newArray(238,52,210); 	/* #EE34D2 */
		else if (colorName == "hot_magenta") cA = newArray(255,0,204);			/* #FF00CC AKA Purple Pizzazz */
		else if (colorName == "outrageous_orange") cA = newArray(255,96,55);	/* #FF6037 */
		else if (colorName == "supernova_orange") cA = newArray(255,191,63);	/* FFBF3F Supernova Neon Orange*/
		else if (colorName == "sunglow") cA = newArray(255,204,51); 			/* #FFCC33 */
		else if (colorName == "neon_carrot") cA = newArray(255,153,51);			/* #FF9933 */
		else if (colorName == "atomic_tangerine") cA = newArray(255,153,102);	/* #FF9966 */
		else if (colorName == "laser_lemon") cA = newArray(255,255,102); 		/* #FFFF66 "Unmellow Yellow" */
		else if (colorName == "electric_lime") cA = newArray(204,255,0); 		/* #CCFF00 */
		else if (colorName == "screamin'_green") cA = newArray(102,255,102); 	/* #66FF66 */
		else if (colorName == "magic_mint") cA = newArray(170,240,209); 		/* #AAF0D1 */
		else if (colorName == "blizzard_blue") cA = newArray(80,191,230); 		/* #50BFE6 Malibu */
		else if (colorName == "dodger_blue") cA = newArray(9,159,255);			/* #099FFF Dodger Neon Blue */
		else restoreExit("No color match to " + colorName);
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
	function pad(n) {
	  /* This version by Tiago Ferreira 6/6/2022 eliminates the toString macro function */
	  if (lengthOf(n)==1) n= "0"+n; return n;
	  if (lengthOf(""+n)==1) n= "0"+n; return n;
	}
	function getHexColorFromRGBArray(colorNameString) {
		colorArray = getColorArrayFromColorName(colorNameString);
		 r = toHex(colorArray[0]); g = toHex(colorArray[1]); b = toHex(colorArray[2]);
		 hexName= "#" + ""+pad(r) + ""+pad(g) + ""+pad(b);
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
		getLut(reds, greens, blues);
		hexColors= newArray(256);
		for (i=0; i<256; i++) {
			r= toHex(reds[i]); g= toHex(greens[i]); b= toHex(blues[i]);
			hexColors[i]= ""+ pad(r) +""+ pad(g) +""+ pad(b);
		}
		return hexColors;
	}
	/*
	End of Color Functions
	*/
  	function getFontChoiceList() {
		/*	v180723 first version
			v180828 Changed order of favorites
			v190108 Longer list of favorites
		*/
		systemFonts = getFontList();
		IJFonts = newArray("SansSerif", "Serif", "Monospaced");
		fontNameChoice = Array.concat(IJFonts,systemFonts);
		faveFontList = newArray("Your favorite fonts here", "Open Sans ExtraBold", "Fira Sans ExtraBold", "Noto Sans Black", "Arial Black", "Montserrat Black", "Lato Black", "Roboto Black", "Merriweather Black", "Alegreya Black", "Tahoma Bold", "Calibri Bold", "Helvetica", "SansSerif", "Calibri", "Roboto", "Tahoma", "Times New Roman Bold", "Times Bold", "Serif");
		faveFontListCheck = newArray(faveFontList.length);
		counter = 0;
		for (i=0; i<faveFontList.length; i++) {
			for (j=0; j<fontNameChoice.length; j++) {
				if (faveFontList[i] == fontNameChoice[j]) {
					faveFontListCheck[counter] = faveFontList[i];
					counter +=1;
					j = fontNameChoice.length;
				}
			}
		}
		faveFontListCheck = Array.trim(faveFontListCheck, counter);
		fontNameChoice = Array.concat(faveFontListCheck,fontNameChoice);
		return fontNameChoice;
	}
	function getSelectionFromMask(sel_M){
		/* v220920 inverts selection if full width */
		batchMode = is("Batch Mode"); /* Store batch status mode before toggling */
		if (!batchMode) setBatchMode(true); /* Toggle batch mode on if previously off */
		tempID = getImageID();
		selectWindow(sel_M);
		run("Create Selection"); /* Selection inverted perhaps because the mask has an inverted LUT? */
		getSelectionBounds(gSelX,gSelY,gWidth,gHeight);
		if(gSelX==0 && gSelY==0 && gWidth==Image.width && gHeight==Image.height)	run("Make Inverse");
		run("Select None");
		selectImage(tempID);
		run("Restore Selection");
		if (!batchMode) setBatchMode(false); /* Return to original batch mode setting */
	}
	function guessBGMedianIntensity(){
		/* v220822 1st color array version (based on https://wsr.imagej.net//macros/tools/ColorPickerTool.txt) */
		iW = Image.width-1;
		iH = Image.height-1;
		interrogate = round(maxOf(1,(iW+iH)/200));
		if (bitDepth==24){red = 0; green = 0; blue = 0;}
		else int = 0;
		xC = newArray(0,iW,0,iW);
		yC = newArray(0,0,iH,iH);
		xAdd = newArray(1,-1,1,-1);
		yAdd = newArray(1,1,-1,-1);
		if (bitDepth==24){ reds = newArray(); greens = newArray(); blues = newArray();}
		else ints = newArray;
		for (i=0; i<xC.length; i++){
			for(j=0;j<interrogate;j++){
				if (bitDepth==24){
					v = getPixel(xC[i]+j*xAdd[i],yC[i]+j*yAdd[i]);
					reds = Array.concat(reds,(v>>16)&0xff);  // extract red byte (bits 23-17)
	           		greens = Array.concat(greens,(v>>8)&0xff); // extract green byte (bits 15-8)
	            	blues = Array.concat(blues,v&0xff);       // extract blue byte (bits 7-0)
				}
				else ints = Array.concat(ints,getValue(xC[i]+j*xAdd[i],yC[i]+j*yAdd[i]));
			}
		}
		midV = round((xC.length-1)/2);
		if (bitDepth==24){
			reds = Array.sort(reds); greens = Array.sort(greens); blues = Array.sort(blues);
			medianVals = newArray(reds[midV],greens[midV],blues[midV]);
		}
		else{
			ints = Array.sort(ints);
			medianVals = newArray(ints[midV],ints[midV],ints[midV]);
		}
		return medianVals;
	}
	function indexOfArray(array,string,default) {
		/* v190423 Adds "default" parameter (use -1 for backwards compatibility). Returns only first found value */
		index = default;
		for (i=0; i<lengthOf(array); i++){
			if (array[i]==string) {
				index = i;
				i = lengthOf(array);
			}
		}
		return index;
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
		cWidth = getWidth()+2; cHeight = getHeight()+2;
		run("Canvas Size...", "width="+cWidth+" height="+cHeight+" position=Center zero");
		floodFill(0, 0);
		makeRectangle(1, 1, cWidth-2, cHeight-2);
		run("Crop");
		showStatus("Remove_Edge_Objects function complete");
		Color.setForeground(originalFGCol);
	}
	function removeTrailingZerosAndPeriod(string) { /* Removes any trailing zeros after a period
	v210430 totally new version
	Note: Requires remTZeroP function
	Nested string functions require "" prefix
	*/
		lIP = lastIndexOf(string, ".");
		if (lIP>=0) {
			lIP = lengthOf(string) - lIP;
			string = "" + remTZeroP(string,lIP);
		}
		return string;
	}
	function remTZeroP(string,iterations){
		for (i=0; i<iterations; i++){
			if (endsWith(string,"0"))
				string = substring(string,0,lengthOf(string)-1);
			else if (endsWith(string,"."))
				string = substring(string,0,lengthOf(string)-1);
			/* Must be "else if" because we only want one removal per iteration */
		}
		return string;
	}
	function restoreExit(message){ /* Make a clean exit from a macro, restoring previous settings */
		/* v200305 1st version using memFlush function */
		restoreSettings(); /* Restore previous settings before exiting */
		setBatchMode("exit & display"); /* Probably not necessary if exiting gracefully but otherwise harmless */
		memFlush(200);
		exit(message);
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
		v210924: Tries to make sure string stays as string
		v211014: Adds some additional cleanup
		v211025: fixes multiple knowns issue
		v211101: Added ".Ext_" removal
		v211104: Restricts cleanup to end of string to reduce risk of corrupting path
		v211112: Tries to fix trapped extension before channel listing. Adds xlsx extension.
		v220615: Tries to fix the fix for the trapped extensions ...
		v230504: Protects directory path if included in string. Only removes doubled spaces and lines.
		v230505: Unwanted dupes replaced by unusefulCombos.
		*/
		fS = File.separator;
		string = "" + string;
		protectedPathEnd = lastIndexOf(string,fS)+1;
		if (protectedPathEnd>0){
			protectedPath = substring(string,0,protectedPathEnd);
			string = substring(string,protectedPathEnd);
		}
		unusefulCombos = newArray("-", "_"," ");
		for (i=0; i<lengthOf(unusefulCombos); i++){
			for (j=0; j<lengthOf(unusefulCombos); j++){
				combo = unusefulCombos[i] + unusefulCombos[j];
				while (indexOf(string,combo)>=0) string = replace(string,combo,unusefulCombos[i]);
			}
		}
		if (lastIndexOf(string, ".")>0 || lastIndexOf(string, "_lzw")>0) {
			knownExt = newArray("dsx", "DSX", "tif", "tiff", "TIF", "TIFF", "png", "PNG", "GIF", "gif", "jpg", "JPG", "jpeg", "JPEG", "jp2", "JP2", "txt", "TXT", "csv", "CSV","xlsx","XLSX");
			kEL = knownExt.length;
			chanLabels = newArray("\(red\)","\(green\)","\(blue\)");
			for (i=0; i<kEL; i++) {
				kExtn = "." + knownExt[i];
				for (j=0; j<3; j++){ /* Looking for channel-label-trapped extensions */
					iChanLabels = lastIndexOf(string, chanLabels[j])-1;
					if (iChanLabels>0){
						preChan = substring(string,0,iChanLabels);
						postChan = substring(string,iChanLabels);
						while (indexOf(preChan,kExtn)>=0) string = replace(preChan,kExtn,"") + postChan;
					}
				}
				while (endsWith(string,kExtn)) string = "" + substring(string, 0, lastIndexOf(string, kExtn));
			}
		}
		unwantedSuffixes = newArray("_lzw"," ", "_","-");
		for (i=0; i<unwantedSuffixes.length; i++){
			while (endsWith(string,unwantedSuffixes[i])) string = substring(string,0,string.length-lengthOf(unwantedSuffixes[i])); /* cleanup previous suffix */
		}
		if (protectedPathEnd>0){
			if(!endsWith(protectedPath,fS)) protectedPath += fS;
			string = protectedPath + string;
		}
		return string;
	}
	function stripUnitFromString(string) {
		if (endsWith(string,"\)")) { /* Label with units from string if enclosed by parentheses */
			unitIndexStart = lastIndexOf(string, "\(");
			unitIndexEnd = lastIndexOf(string, "\)");
			stringUnit = substring(string, unitIndexStart+1, unitIndexEnd);
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
		/* Replaces binary[-]Check function
		v220707
		*/
		selectWindow(windowTitle);
		if (!is("binary")) run("8-bit");
		/* Quick-n-dirty threshold if not previously thresholded */
		getThreshold(t1,t2);
		if (t1==-1)  {
			run("8-bit");
			run("Auto Threshold", "method=Default");
			setOption("BlackBackground", false);
			run("Make Binary");
		}
		if (is("Inverting LUT")) run("Invert LUT");
		/* Make sure black objects on white background for consistency */
		yMax = Image.height-1;	xMax = Image.width-1;
		cornerPixels = newArray(getPixel(0,0),getPixel(1,1),getPixel(0,yMax),getPixel(xMax,0),getPixel(xMax,yMax),getPixel(xMax-1,yMax-1));
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
	*/
		/* Remove bad characters */
		string = string.replace(fromCharCode(178), "\\^2"); /* superscript 2 */
		string = string.replace(fromCharCode(179), "\\^3"); /* superscript 3 UTF-16 (decimal) */
		string = string.replace(fromCharCode(0xFE63) + fromCharCode(185), "\\^-1"); /* Small hyphen substituted for superscript minus as 0x207B does not display in table */
		string = string.replace(fromCharCode(0xFE63) + fromCharCode(178), "\\^-2"); /* Small hyphen substituted for superscript minus as 0x207B does not display in table */
		string = string.replace(fromCharCode(181)+"m", "um"); /* micron units */
		string = string.replace(getInfo("micrometer.abbreviation"), "um"); /* micron units */
		string = string.replace(fromCharCode(197), "Angstrom"); /* Ångström unit symbol */
		string = string.replace(fromCharCode(0x212B), "Angstrom"); /* the other Ångström unit symbol */
		string = string.replace(fromCharCode(0x2009) + fromCharCode(0x00B0), "deg"); /* replace thin spaces degrees combination */
		string = string.replace(fromCharCode(0x2009), "_"); /* Replace thin spaces  */
		string = string.replace("%", "pc"); /* % causes issues with html listing */
		string = string.replace(" ", "_"); /* Replace spaces - these can be a problem with image combination */
		/* Remove duplicate strings */
		unwantedDupes = newArray("8bit","8-bit","lzw");
		for (i=0; i<lengthOf(unwantedDupes); i++){
			iLast = lastIndexOf(string,unwantedDupes[i]);
			iFirst = indexOf(string,unwantedDupes[i]);
			if (iFirst!=iLast) {
				string = string.substring(0,iFirst) + string.substring(iFirst + lengthOf(unwantedDupes[i]));
				i=-1; /* check again */
			}
		}
		unwantedDbls = newArray("_-","-_","__","--","\\+\\+");
		for (i=0; i<lengthOf(unwantedDbls); i++){
			iFirst = indexOf(string,unwantedDbls[i]);
			if (iFirst>=0) {
				string = string.substring(0,iFirst) + string.substring(string,iFirst + lengthOf(unwantedDbls[i])/2);
				i=-1; /* check again */
			}
		}
		string = string.replace("_\\+", "\\+"); /* Clean up autofilenames */
		/* cleanup suffixes */
		unwantedSuffixes = newArray(" ","_","-","\\+"); /* things you don't wasn't to end a filename with */
		extStart = lastIndexOf(string,".");
		sL = lengthOf(string);
		if (sL-extStart<=4 && extStart>0) extIncl = true;
		else extIncl = false;
		if (extIncl){
			preString = substring(string,0,extStart);
			extString = substring(string,extStart);
		}
		else {
			preString = string;
			extString = "";
		}
		for (i=0; i<lengthOf(unwantedSuffixes); i++){
			sL = lengthOf(preString);
			if (endsWith(preString,unwantedSuffixes[i])) {
				preString = substring(preString,0,sL-lengthOf(unwantedSuffixes[i])); /* cleanup previous suffix */
				i=-1; /* check one more time */
			}
		}
		if (!endsWith(preString,"_lzw") && !endsWith(preString,"_lzw.")) preString = replace(preString, "_lzw", ""); /* Only want to keep this if it is at the end */
		string = preString + extString;
		/* End of suffix cleanup */
		return string;
	}
	function unitLabelFromString(string, imageUnit) {
	/* v180404 added Feret_MinDAngle_Offset
		v210823 REQUIRES ASC function indexOfArray(array,string,default) for expanded "unitless" array.
		v220808 Replaces ° with fromCharCode(0x00B0).
		v230109 Expand px to pixels. Simpify angleUnits.
		*/
		if (endsWith(string,"\)")) { /* Label with units from string if enclosed by parentheses */
			unitIndexStart = lastIndexOf(string, "\(");
			unitIndexEnd = lastIndexOf(string, "\)");
			stringUnit = substring(string, unitIndexStart+1, unitIndexEnd);
			unitCheck = matches(stringUnit, ".*[0-9].*");
			if (unitCheck==0) {  /* If the "unit" contains a number it probably isn't a unit unless it is the 0-90 degress setting */
				unitLabel = stringUnit;
			}
			else if (indexOf(stringUnit,"0-90")<0 || indexOf(stringUnit,"0to90")<0) unitLabel = fromCharCode(0x00B0);
			else {
				unitLabel = "";
			}
		}
		else {
			unitLess = newArray("Circ.","Slice","AR","Round","Solidity","Image_Name","PixelAR","ROI_name","ObjectN","AR_Box","AR_Feret","Rnd_Feret","Compact_Feret","Elongation","Thinnes_Ratio","Squarity_AP","Squarity_AF","Squarity_Ff","Convexity","Rndnss_cAR","Fbr_Snk_Crl","Fbr_Rss2_Crl","AR_Fbr_Snk","Extent","HSF","HSFR","Hexagonality");
			angleUnits = newArray("Angle","FeretAngle","Cir_to_El_Tilt","0-90",fromCharCode(0x00B0),"0to90","degrees");
			chooseUnits = newArray("Mean" ,"StdDev" ,"Mode" ,"Min" ,"Max" ,"IntDen" ,"Median" ,"RawIntDen" ,"Slice");
			if (string=="Area") unitLabel = imageUnit + fromCharCode(178);
			else if (indexOfArray(unitLess,string,-1)>=0) unitLabel = "None";
			else if (indexOfArray(chooseUnits,string,-1)>=0) unitLabel = "";
			else if (indexOfArray(angleUnits,string,-1)>=0) unitLabel = fromCharCode(0x00B0);
			else if (string=="%Area") unitLabel = "%";
			else unitLabel = imageUnit;
			if (indexOf(unitLabel,"px")>=0) unitLabel = "pixels";
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
	This version adds a summary table anywhere you want it but the dialog box may be too long for some monitors: 8/9/2016
	Adjusted to allow Grays-only if selected and default to white background.
	Added the ability to added user-text to summary and data preview in summary dialog.
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
	+ v180302 Object and Summary Labels: moved formatting to function and unitless comma removed from ramp label.
	+ v180315 Reordered 1st menu.
	+ v180316 added option of adding colored outline around outliers.
	+ v180317 Corrected yellow color and added primary colors as better outlier highlights.
	+ v180319 Added log stats output options, increased sigma option up to 4sigma and further refined initial dialog.
	+ v180321 Added mode statistics to summary and fixed inconsistent decimal places in summary.
	+ v180323 Further tweaks to the histogram appearance and a fix for instances where the mode is in the 1st bin.
	+ v180323b Adds options to crop image before combining with ramp. Also add options to skip adding labels.
	+ v180326 Adds "Manual_Input" option to outliers (use this option for sigma>3).
	+ v180326 Restored missing frequency distribution column.
	+ v180329 Changed line width for frequency plot to work better for very large images.
	+ v180402 Reordered dialogs for space efficiency, fixed outlier choice menu item, described font size basis in menu.
	+ v180403 Changed min-max and SD label limits to prevent overlap of SD and min-max labels (min-max labels take priority).
	+ v180404 Fixed above. 	+ v180601 Adds choice to invert and choice of images. + v180602 Added MC-Centroid 0.5 pixel offset.
	+ v180716 Fixed unnecessary bailout for small distributions that do not produce an interquartile range.
	+ v180717 More fixes for small distributions that do not produce an interquartile range.
	+ v180718 Reorganized ramp options to make ramp labels easy to edit.
	+ v180719 Fixed formatting so that Labels and Summaries have different settings. Added title-only option. Added margin to auto-crop.
	+ v180722 Allows any system font to be used. Fixed selected positions.
	+ v180725 Adds outlier color to right hand ticks within outlier range in ramp.
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
	+ v190802 Fixed missing +1 sigma outlier ramp labels. Adjusted sigma range to allow display closer to top of ramp.
	+ v200305 Added shorter dialogs for lower resolution screens and added memory flushing function.
	+ v200604 Removed troublesome macro-path determination
	+ v200706 Changed imageDepth variable name.
	+ v210415 bug fix in 2nd dialog
	+ v210416-9 Improved menu options and various bug fixes. Updated ASC functions to latest versions.
	+ v210420-2 Replaced non-working coded range with LUT range option. v210422 bug fixes.
	+ v210429-v210503 Expandable arrays. Better ramp label optimization. Fixed image combination issue. Added auto-trimming of object labels option, corrected number of minor ticks
	+ v210820 Added "Sum" to summary parameters, fixed acceptable range for Mean label, changed unit recognition function
	+ v210823-5 Optional expansions of parameter labels to be more informative. Added option to quickly apply simple black text formatting for summary table.
	+ v210826 Added guessBGMedianIntensity function for no-Shadow summary alternative
	+ v211021 Outliers and outlier counts for < > values can be different colors. If different colors are chosen they can be listed separately in the summary.
	+ v211022 All colors lower-case, restored cyan.
	+ v211025 Updated functions
	+ v211029 Fixed missing comment close below. Added cividis.lut to favorite luts
	+ v211104: Updated stripKnownExtensionFromString function    v211112: Again
	+ v211119: Added option to perform to create a Max calculated version to restore holes (not fully tested yet in all circumstances). Added skip options to summary choices.
	+ v220113: Adds summary output options to include output to log window or both image and log window
	+ v220701: Updates functions and adds message in summary options dialog to show output destination.
	+ v220706: Does not require binary image. f1: updated colors and v220707 replaced binary[-]Check with toWhiteBGBinary so it is more explicit.
	+ v220708: Reorganized menus to allow for more lines of statistics. f1-2: Updated color functions.
	+ v221208: fixed missing parentesis in line 1295, correct out of date hyperlink, addressed missing outlier outline issue
	+ v221209: fixed ln stats array length error.
	+ v230109: Improvements to parameter label expansion.
	*/