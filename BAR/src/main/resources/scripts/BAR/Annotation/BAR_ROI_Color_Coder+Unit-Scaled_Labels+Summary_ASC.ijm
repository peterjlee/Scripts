/*	Fork of ROI_Color_Coder.ijm IJ BAR: https://github.com/tferr/Scripts#scripts
	https://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder
	Colorizes ROIs by matching LUT indexes to measurements in the Results table.
	Based on Tiago Ferreira, v.5.4 2017.03.10
	Peter J. Lee Applied Superconductivity Center, NHMFL  v200305
	Full history at the bottom of the file.
	v190802
 */
 
macro "ROI Color Coder with Scaled Labels and Summary"{
	requires("1.47r");
	run("Collect Garbage");
	if (!checkForPluginNameContains("Fiji_Plugins")) exit("Sorry this macro requires some functions in the Fiji_Plugins package");
	/* Needs Fiji_pluings for autoCrop */
	saveSettings;
	close("*Ramp"); /* cleanup: closes previous ramp windows */
	if (nImages==0){
		showMessageWithCancel("No images open or the ROI Manager is empty...\n"
        + "Run demo? (Results Table and ROI Manager will be cleared)");
	    runDemo();
	}
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
	run("Appearance...", " "); if(is("Inverting LUT")) run("Invert LUT"); /* do not use Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background) http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	id = getImageID();	t=getTitle(); /* get id of image and title */
	checkForUnits(); /* Required function */
	getPixelSize(unit, pixelWidth, pixelHeight);
	lcf=(pixelWidth+pixelHeight)/2; /* length conversion factor needed for morph. centroids */
	checkForRoiManager(); /* macro requires that the objects are in the ROI manager */
	checkForResults(); /* macro requires that there are results to display */
	nROIs = roiManager("count"); /* get number of ROIs to colorize */
	nRes = nResults;
	countNaN = 0; /* Set this counter here so it is not skipped by later decisions */
	menuLimit = 0.8 * screenHeight; /* used to limit menu size for small screens */
	// menuLimit = 700; /* for testing only resolution options only */
	numLabels = 10; /* default number of ramp labels */
	sup2 = fromCharCode(178);
	ums = getInfo("micrometer.abbreviation");
	if (nRes!=nROIs) restoreExit("Exit: Results table \(" + nRes + "\) and ROI Manager \(" + nROIs + "\) mismatch."); /* exit so that this ambiguity can be cleared up */
	if (nROIs<=1) restoreExit("Exit: ROI Manager has only \(" + nROIs + "\) entries."); /* exit so that this ambiguity can be cleared up */
	items = nROIs;
	run("Remove Overlay");
	setBatchMode(true);
	tN = stripKnownExtensionFromString(unCleanLabel(t)); /* File.nameWithoutExtension is specific to last opened file, also remove special characters that might cause issues saving file */
	imageHeight = getHeight(); imageWidth = getWidth();
	rampH = round(0.89 * imageHeight); /* suggest ramp slightly small to allow room for labels */
	acceptMinFontSize = true;
	fontSize = maxOf(10,imageHeight/28); /* default fonts size based on imageHeight */
	originalImageDepth = bitDepth(); /* required for shadows at different bit depths */
	headings = split(String.getResultsHeadings, "\t"); /* the tab specificity avoids problems with unusual column titles */
	headingsWithRange= newArray(lengthOf(headings));
	for (i=0; i<lengthOf(headings); i++) {
		resultsColumn = newArray(items);
		for (j=0; j<items; j++)
			resultsColumn[j] = getResult(headings[i], j);
		Array.getStatistics(resultsColumn, min, max, null, null); 
		headingsWithRange[i] = headings[i] + ":  " + min + " - " + max;
	}
	if (headingsWithRange[0]==" :  Infinity - -Infinity")
		headingsWithRange[0] = "Object" + ":  1 - " + items; /* relabels ImageJ ID column */
	imageList = getList("image.titles");
	/* Create initial dialog prompt to determine parameters */
	macroP = getInfo("macro.filepath");
	macroL = substring(macroP, lastIndexOf(macroP, "\\") + 1, lastIndexOf(macroP, ".ijm" ));
	if (macroL.length>43) macroL = macroL.substring(0,21) + "..." + macroL.substring(macroL.length-21);
	tNL = tN;
	if (tN.length>43) tNL = tNL.substring(0,21) + "..." + tNL.substring(tNL.length-21);
	Dialog.create("ROI Color Coder: " + tN);
		/* if called from the BAR menu there will be no macro.filepath so the following checks for that */
		if (macroP=="null") Dialog.addMessage("Macro: ASC fork of BAR ROI Color Coder with Scaled Labels and Summary");
		else Dialog.addMessage("Macro: " + macroL);
		Dialog.setInsets(6, 0, 0);
		Dialog.addMessage("Filename: " + tNL);
		Dialog.addMessage("Image has " + nROIs + " ROIs that will be color coded.");
		Dialog.setInsets(10, 0, 10);
		Dialog.addChoice("Image for Coloring", imageList, t);
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
		allColors = newArray("red", "pink", "green", "blue", "yellow", "orange", "garnet", "gold", "aqua_modern", "blue_accent_modern", "blue_dark_modern", "blue_modern", "gray_modern", "green_dark_modern", "green_modern", "orange_modern", "pink_modern", "purple_modern", "jazzberry_jam", "red_N_modern", "red_modern", "tan_modern", "violet_modern", "yellow_modern", "Radical Red", "Wild Watermelon", "Outrageous Orange", "Atomic Tangerine", "Neon Carrot", "Sunglow", "Laser Lemon", "Electric Lime", "Screamin' Green", "Magic Mint", "Blizzard Blue", "Shocking Pink", "Razzle Dazzle Rose", "Hot Magenta");
		Dialog.addChoice("Outliers: Outline:", allColors, allColors[0]);
		Dialog.addCheckbox("Apply colors and labels to image copy \(no change to original\)", true);
		Dialog.setInsets(6, 120, 10);
		if (selectionExists) {
			Dialog.addCheckbox("Summary/Parameter at selected location \(below\)?", true); 
			Dialog.addNumber("Starting",selPosStartX,0,5,"X");
			Dialog.setInsets(-28, 150, 0);
			Dialog.addNumber("Starting",selPosStartY,0,5,"Y");
			Dialog.addNumber("Selected",originalSelEWidth,0,5,"Width");
			Dialog.setInsets(-28, 150, 0);
			Dialog.addNumber("Selected",originalSelEHeight,0,5,"Height");
		}
	Dialog.show;
		imageChoice = Dialog.getChoice;
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
		addLabels = Dialog.getCheckbox;
		if (selectionExists) {
			selectionExists = Dialog.getCheckbox; 
			selPosStartX = Dialog.getNumber;
			selPosStartY = Dialog.getNumber;
			originalSelEWidth = Dialog.getNumber;
			originalSelEHeight = Dialog.getNumber;
		}
	unitLabel = unitLabelFromString(parameter, unit);
	/* get values for chosen parameter */
	values= newArray(items);
	if (parameter=="Object") for (i=0; i<items; i++) values[i]= i+1;
	else for (i=0; i<items; i++) values[i]= getResult(parameter,i);
	Array.getStatistics(values, arrayMin, arrayMax, arrayMean, arraySD); 
	arrayRange = arrayMax-arrayMin;	
	rampMin= arrayMin;
	rampMax= arrayMax;
	decPlaces = autoCalculateDecPlaces4(decPlaces,rampMin,rampMax,numLabels);
	/* Create dialog prompt to determine look */
	Dialog.create("ROI Color Coder: Ramp options");		
		Dialog.setInsets(2, 0, 6);
		Dialog.addMessage("Legend \(ramp\) options:");
		Dialog.addString("Parameter label", parameter, 24);
		Dialog.setInsets(-42, 315, -5);
		Dialog.addMessage("Edit for\nramp label");
		autoUnit = unitLabelFromString(parameter, unit);
		unitChoice = newArray(autoUnit, "Manual", unit, unit+sup2, "None", "pixels", "pixels"+sup2, fromCharCode(0x00B0), "degrees", "radians", "%", "arb.");
		if (unit=="microns" && (autoUnit!=ums || autoUnit!=ums+sup2)) unitChoice = Array.concat(newArray(ums,ums+sup2),unitChoice);
		Dialog.addChoice("Unit \("+unit+"\) Label:", unitChoice, unitChoice[0]);
		Dialog.setInsets(-42, 215, -5);
		Dialog.addMessage("Auto based on\nselected parameter");
		Dialog.addMessage("Original data range: "+rampMin+"-"+rampMax+" \("+(rampMax-rampMin)+" "+unit+"\)");
		Dialog.addString("Ramp data range:", rampMin+"-"+rampMax, 11);
		Dialog.addString("Color Coded Range:", rampMin+"-"+rampMax, 11);
		Dialog.setInsets(-35, 240, 0);
		Dialog.addMessage("(e.g., 10-100)");
		Dialog.setInsets(-4, 120, 0);
		Dialog.addCheckbox("Add ramp labels at Min. & Max. if inside Range", true);
		Dialog.addNumber("No. of intervals:", 10, 0, 3, "Defines major ticks/label spacing");
		Dialog.addNumber("Minor tick intervals:", 0, 0, 3, "5 would add 4 ticks between labels ");
		Dialog.addChoice("Decimal places:", newArray("Auto", "Manual", "Scientific", "0", "1", "2", "3", "4"), "Auto");
		Dialog.addChoice("Ramp height \(pxls\):", newArray(d2s(rampH,0), 128, 256, 512, 1024, 2048, 4096), rampH);
		Dialog.setInsets(-38, 235, 0);
		Dialog.addMessage(rampH + " pxls suggested\nby image height");
		fontStyleChoice = newArray("bold", "bold antialiased", "italic", "italic antialiased", "bold italic", "bold italic antialiased", "unstyled");
		Dialog.addChoice("Font style:", fontStyleChoice, fontStyleChoice[1]);
		fontNameChoice = getFontChoiceList();
		Dialog.addChoice("Font name:", fontNameChoice, fontNameChoice[0]);
		Dialog.addNumber("Font_size \(height\):", fontSize, 0, 3, "pxls");
		Dialog.setInsets(-25, 235, 0);
		Dialog.addCheckbox("Draw tick marks", true);
		Dialog.setInsets(2, 120, 0);
		Dialog.addCheckbox("Force clockwise rotated legend label", false);
		Dialog.setInsets(3, 0, -2);
		// Dialog.addMessage("Statistics labels added to legend \(ramp\):");
		// Dialog.setInsets(6, 120, -20);
		rampStatsOptions = newArray("No", "Linear", "Ln");
		Dialog.setInsets(-20, 15, 18);
		Dialog.addRadioButtonGroup("Ramp Stats: Mean and " + fromCharCode(0x00B1) + fromCharCode(0x03C3) + " on ramp \(if \"Ln\" then outlier " + fromCharCode(0x03C3) + " will be \"Ln\" too\)", rampStatsOptions, 1, 5, "No");
		/* will be used for sigma outlines too */
		Dialog.addNumber("Tick length:", 50, 0, 3, "% of major tick. Also Min. & Max. Lines");
		Dialog.addNumber("Label font:", 100, 0, 3, "% of font size. Also Min. & Max. Lines");
		Dialog.setInsets(4, 120, 0);
		Dialog.addCheckbox("Add Frequency Distribution Plot to Ramp", false);
		Dialog.addHelp("http://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder");
	Dialog.show;
		parameterLabel = Dialog.getString;
		unitLabel = Dialog.getChoice();
		rangeS = Dialog.getString; /* changed from original to allow negative values - see below */
		rangeCoded = Dialog.getString;
		minmaxLines = Dialog.getCheckbox;
		numLabels = Dialog.getNumber + 1; /* The number of major ticks/labels is one more than the intervals */
		minorTicks = Dialog.getNumber; /* The number of major ticks/labels is one more than the intervals */
		dpChoice = Dialog.getChoice;
		rampHChoice = parseInt(Dialog.getChoice);
		fontStyle = Dialog.getChoice;
			if (fontStyle=="unstyled") fontStyle="";
		fontName = Dialog.getChoice;
		fontSize = Dialog.getNumber;
		ticks = Dialog.getCheckbox;
		rotLegend = Dialog.getCheckbox;
		statsRampLines = Dialog.getRadioButton;
		statsRampTicks = Dialog.getNumber;
		thinLinesFontSTweak = Dialog.getNumber;
		freqDistRamp = Dialog.getCheckbox();
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
	if (statsRampLines=="Ln") rampParameterLabel= rampParameterLabel + "\(ln stats\)";
	rampUnitLabel = replace(unitLabel, fromCharCode(0x00B0), "degrees"); /* replace lonely ° symbol */
	if ((rotLegend && (rampHChoice==rampH)) || (rampW < maxOf(getStringWidth(rampUnitLabel), getStringWidth(rampParameterLabel)))) rampH = imageHeight - fontSize; /* tweaks automatic height selection for vertical legend */
	else rampH = rampHChoice;
	rampW = round(rampH/8); 
	range = split(rangeS, "-");
	if (lengthOf(range)==1) {
		rampMin= NaN; rampMax= parseFloat(range[0]);
	} else {
		rampMin= parseFloat(range[0]); rampMax= parseFloat(range[1]);
	}
	if (indexOf(rangeS, "-")==0) rampMin = 0 - rampMin; /* checks to see if rampMin is a negative value (lets hope the rampMax isn't). */
	
	codedRange = split(rangeCoded, "-");
	if (lengthOf(codedRange)==1) {
		minCoded = NaN; maxCoded = parseFloat(codedRange[0]);
	} else {
		minCoded = parseFloat(codedRange[0]); maxCoded = parseFloat(codedRange[1]);
	}
	if (indexOf(rangeCoded, "-")==0) minC = 0 - minC; /* checks to see if min is a negative value (lets hope the max isn't). */	
	fontSR2 = fontSize * thinLinesFontSTweak/100;
	rampLW = maxOf(1, round(rampH/512)); /* ramp line width with a minimum of 1 pixel */
	minmaxLW = round(rampLW / 4); /* line widths for ramp stats */
	if (isNaN(rampMin)) rampMin = arrayMin;
	if (isNaN(rampMax)) rampMax = arrayMax;
	if (isNaN(minCoded)) minCoded = arrayMin;
	if (isNaN(maxCoded)) maxCoded = arrayMax;
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
	else freqDistRamp=false;
	meanPlusSDs = newArray(10);
	meanMinusSDs = newArray(10);
	for (s=0; s<10; s++) {
		meanPlusSDs[s] = arrayMean+(s*arraySD);
		meanMinusSDs[s] = arrayMean-(s*arraySD);
	}
	/* Calculate ln stats for summary and also ramp if requested */
	lnValues = lnArray(values);
	Array.getStatistics(lnValues, null, null, lnMean, lnSD);
	expLnMeanPlusSDs = newArray(10);
	expLnMeanMinusSDs = newArray(10);
	expLnSD = exp(lnSD);
	for (s=0; s<10; s++) {
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
	if (unitLabel=="None") unitLabel = ""; 
	unitLabel= cleanLabel(unitLabel);
	/* Begin object color coding if stroke set */
	if (stroke>=0) {
		/*	Create LUT-map legend	*/
		rampTBMargin = 2 * fontSize;
		canvasH = round(2 * rampTBMargin + rampH);
		canvasH = round(4 * fontSize + rampH);
		canvasW = round(rampH/2);
		tickL = round(rampW/4);
		if (statsRampLines!="No" || minmaxLines) tickL = round(tickL/2); /* reduce tick length to provide more space for inside label */
		tickLR = round(tickL * statsRampTicks/100);
		getLocationAndSize(imgx, imgy, imgwidth, imgheight);
		call("ij.gui.ImageWindow.setNextLocation", imgx+imgwidth, imgy);
		newImage(tN + "_" + parameterLabel +"_Ramp", "8-bit ramp", rampH, rampW, 1); /* Height and width swapped for later rotation */
		/* ramp color/gray range is horizontal only so must be rotated later */
		if (revLut) run("Flip Horizontally");
		tR = getTitle; /* short variable label for ramp */
		roiColors= loadLutColors(lut); /* load the LUT as a hexColor array: requires function */
		/* continue the legend design */
		/* Frequency line if requested */
		if (freqDistRamp) {
			rampRXF = rampH/(rampMax-rampMin); /* RXF short for Range X Factor Units/pixel */
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
		if (originalImageDepth!=8 || lut!="Grays") run("RGB Color"); /* converts ramp to RGB if not using grays only */
		setLineWidth(rampLW*2);
		if (ticks) {
			drawRect(0, 0, rampH, rampW);
			/* The next steps add the top and bottom ticks */
			rampWT = rampW + 2*rampLW;
			run("Canvas Size...", "width=&rampH height=&rampWT position=Top-Center");
			setLineWidth(rampLW*1.5);
			drawLine(0, 0, 0, rampW-1 + rampLW); /* Draw full width line at top an bottom */
			drawLine(rampH-1, 0, rampH-1, rampW-1 + rampLW); /* Draw full width line at top an d bottom */
		}
		run("Rotate 90 Degrees Left");
		run("Canvas Size...", "width=&canvasW height=&canvasH position=Center-Left");
		if (dpChoice=="Auto")
			decPlaces = autoCalculateDecPlaces4(decPlaces,rampMin,rampMax,numLabels);
		else if (dpChoice=="Manual") 
			decPlaces=getNumber("Choose Number of Decimal Places", 0);
		else if (dpChoice=="Scientific")
			decPlaces = -1;
		else decPlaces = dpChoice;
		if (parameter=="Object") decPlaces = 0; /* This should be an integer */
		/* draw ticks and values */
		rampOffset = (getHeight-rampH)/2;
		step = rampH;
		if (numLabels>2) step /= (numLabels-1);
		setLineWidth(rampLW);
		for (i=0; i<numLabels; i++) {
			yPos = rampH + rampOffset - i*step -1; /* minus 1 corrects for coordinates starting at zero */
			rampLabel = rampMin + (rampMax-rampMin)/(numLabels-1) * i;
			rampLabelString = removeTrailingZerosAndPeriod(d2s(rampLabel,decPlaces));
			/*Now add overrun text labels at the top and/or bottom of the ramp if the true data extends beyond the ramp range */
			if ((i==0) && (0.98*rampMin>arrayMin)) {
				rampExt = removeTrailingZerosAndPeriod(d2s(arrayMin,decPlaces+1)); /* adding 1 to dp ensures that the range is different */
				rampLabelString = rampExt + "-" + rampLabelString; 
			}if ((i==(numLabels-1)) && ((1.02*rampMax)<arrayMax)) {
				rampExt = removeTrailingZerosAndPeriod(d2s(arrayMax,decPlaces+1));
				rampLabelString += "-" + rampExt; 
			}
			drawString(rampLabelString, rampW+4*rampLW, yPos+numLabelFontSize/1.5);
			if (ticks) {
				if ((i>0) && (i<(numLabels-1))) {
					setLineWidth(rampLW);
					drawLine(0, yPos, tickL, yPos);					/* left tick */
					drawLine(rampW-1-tickL, yPos, rampW, yPos);
					drawLine(rampW, yPos, rampW+rampLW, yPos); /* right tick extends over border slightly as subtle cross-tick */
				}
			}
		}
		setFont(fontName, fontSize, fontStyle);
		/* draw minor ticks */
		if (ticks && (minorTicks>0)) {
			minorTickStep = step/minorTicks;
			for (i=0; i<numLabels*minorTicks; i++) {
				if ((i>0) && (i<(((numLabels-1)*minorTicks)))) {
					yPos = rampH + rampOffset - i*minorTickStep -1; /* minus 1 corrects for coordinates starting at zero */
					setLineWidth(round(rampLW/4));
					drawLine(0, yPos, tickL/4, yPos);					/* left minor tick */
					drawLine(rampW-tickL/4-1, yPos, rampW-1, yPos);		/* right minor tick */
					setLineWidth(rampLW); /* reset line width */
				}
			}
		}
		/* end draw minor ticks */
		/* now add lines and the true min and max and for stats if chosen in previous dialog */
		if ((0.98*rampMin<=arrayMin) && (0.98*rampMax<=arrayMax)) minmaxLines = false;
		if ((rampMin>arrayMin) && (rampMax<arrayMax)) minmaxLines = false; 
		// if (rampMin>arrayMin) minmaxLines = false; /* Temporary fix for empty ramp issue */
		if (minmaxLines || statsRampLines!="No") {
			newImage("label_mask", "8-bit black", getWidth(), getHeight(), 1);
			setColor("white");
			setLineWidth(rampLW);
			minPos = 0; maxPos = rampH; /* to be used in later sd overlap if statement */
			if (minmaxLines) {
				if (rampMin==rampMax) restoreExit("Something terribly wrong with this range!");
				trueMaxFactor = (arrayMax-rampMin)/(rampMax-rampMin);
				maxPos = rampTBMargin + (rampH * (1 - trueMaxFactor))-1;
				trueMinFactor = (arrayMin-rampMin)/(rampMax-rampMin);
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
				rampMeanPlusSDFactors = newArray(10);
				rampMeanMinusSDFactors = newArray(10);
				plusSDPos = newArray(10);
				minusSDPos = newArray(10);
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
				rampRange = rampMax-rampMin;
				for (s=0; s<10; s++) {
					rampMeanPlusSDFactors[s] = (rampMeanPlusSDs[s]-rampMin)/rampRange;
					rampMeanMinusSDFactors[s] = (rampMeanMinusSDs[s]-rampMin)/rampRange;
					plusSDPos[s] = rampTBMargin + (rampH * (1 - rampMeanPlusSDFactors[s])) -1;
					minusSDPos[s] = rampTBMargin + (rampH * (1 - rampMeanMinusSDFactors[s])) -1;
				}
				meanFS = 0.9*fontSR2;
				setFont(fontName, meanFS, fontStyle);
				if ((rampMeanPlusSDs[0]>=1.02*rampMin) && (rampMeanPlusSDs[0]<=0.92*rampMax)) {
					drawString("Mean", round((rampW-getStringWidth("Mean"))/2), plusSDPos[0]+0.75*meanFS);
					drawLine(rampLW, plusSDPos[0], tickLR, plusSDPos[0]);
					drawLine(rampW-1-tickLR, plusSDPos[0], rampW-rampLW-1, plusSDPos[0]);
				}
				lastDrawnPlusSDPos = plusSDPos[0];
				for (s=1; s<10; s++) {
					if ((rampMeanPlusSDFactors[s]<=1) && (plusSDPos[s]<=(rampH - fontSR2)) && (abs(plusSDPos[s]-lastDrawnPlusSDPos)>0.75*fontSR2)) {
						setFont(fontName, fontSR2, fontStyle);
						if (minmaxLines) {
							if (plusSDPos[s]<=(maxPos-0.75*fontSR2) || plusSDPos[s]>=(maxPos+0.75*fontSR2)) { /* prevent overlap with max line */
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
						if (rampMeanPlusSDFactors[minOf(9,s+1)]>=0.98) s = 10;
					}
				}
				lastDrawnMinusSDPos = minusSDPos[0];
				for (s=1; s<10; s++) {
					if ((rampMeanMinusSDFactors[s]>0) && (minusSDPos[s]>fontSR2) && (abs(minusSDPos[s]-lastDrawnMinusSDPos)>0.75*fontSR2)) {
						setFont(fontName, fontSR2, fontStyle);
						if (minmaxLines) {
							if ((minusSDPos[s]<(minPos-0.75*fontSR2)) || (minusSDPos[s]>(minPos+0.75*fontSR2))) { /* prevent overlap with min line */
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
						if (rampMeanMinusSDs[minOf(9,s+1)]<0.93*rampMin) s = 10;
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
			run("Enlarge...", "enlarge=&rampOutlineStroke pixel");
			setBackgroundColor(0, 0, 0);
			run("Clear");
			run("Enlarge...", "enlarge=&rampOutlineStroke pixel");
			run("Gaussian Blur...", "sigma=&rampOutlineStroke");
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
				for (s=1; s<10; s++) {
					if ((outlierChoice!="No") && (s>=sigmaR)) {
						if ((rampMeanPlusSDFactors[s]<=1) && (plusSDPos[s]<=(rampH - fontSR2)) && (abs(plusSDPos[s]-lastDrawnPlusSDPos)>0.75*fontSR2)) {
							if (minmaxLines) {
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
							if (rampMeanPlusSDFactors[minOf(9,s+1)]>=0.98) s = 10;
						}
					}
				}
				lastDrawnMinusSDPos = minusSDPos[0];
				for (s=1; s<10; s++) {
					if ((outlierChoice!="No") && (s>=sigmaR)) {
						if ((rampMeanMinusSDFactors[s]>0) && (minusSDPos[s]>fontSR2) && (abs(minusSDPos[s]-lastDrawnMinusSDPos)>0.75*fontSR2)) {
							if (minmaxLines) {
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
							if (rampMeanMinusSDs[minOf(9,s+1)]<0.93*rampMin) s = 10;
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
			rampParameterLabel = expandLabel(rampParameterLabel);
			rampParameterLabel = replace(rampParameterLabel, fromCharCode(0x2009), " "); /* expand again now we have the space */
			rampParameterLabel = replace(rampParameterLabel, "px", "pixels"); /* expand "px" used to keep Results columns narrower */
			run("Canvas Size...", "width=&canvasH height=&canvasW position=Bottom-Center");
			if (rampParameterLabel!="") drawString(rampParameterLabel, round((canvasH-(getStringWidth(rampParameterLabel)))/2), round(1.5*fontSize));
			run("Rotate 90 Degrees Right");
		}
		autoCropGuessBackgroundSafe();	/* toggles batch mode */
		/* add padding to legend box - better than expanding crop selection as is adds padding to all sides */
		getDisplayedArea(null, null, canvasW, canvasH);
		canvasW += round(imageWidth/150);
		canvasH += round(imageHeight/150);
		run("Canvas Size...", "width=&canvasW height=&canvasH position=Center");
		/*
			iterate through the ROI Manager list and colorize ROIs
		*/
		selectImage(id);
		for (i=0; i<items; i++) {
			if ((values[i]>=minCoded) && (values[i]<=maxCoded)) {
				showStatus("Coloring object " + i + ", " + (nROIs-i) + " more to go");
				roiManager("select", i);
				if (isNaN(values[i])) countNaN += 1;
				if (!revLut) {
					if (values[i]<=rampMin) lutIndex= 0;
					else if (values[i]>rampMax) lutIndex= 255;
					else lutIndex = 255 * (values[i] - rampMin) / (rampMax - rampMin);
				}
				else {
					if (values[i]<=rampMin) lutIndex= 255;
					else if (values[i]>rampMax) lutIndex= 0;
					else lutIndex= 255 * (rampMax - values[i]) / (rampMax - rampMin);
				}
				if (stroke>0) {
					Roi.setStrokeWidth(stroke);
					Roi.setStrokeColor(alpha+roiColors[lutIndex]);
				} else
					Roi.setFillColor(alpha+roiColors[lutIndex]);
				labelValue = values[i];
				labelString = d2s(labelValue,decPlaces); /* Reduce decimal places for labeling (move these two lines to below the labels you prefer) */
				labelString = removeTrailingZerosAndPeriod(labelString); /* Remove trailing zeros and periods */
				roiManager('update');
				Overlay.show;
			}
		}
	}
	/* End of object coloring */

	/* recombine units and labels that were used in Ramp */
	if (unitLabel!="") paraLabel = parameterLabel + ", " + unitLabel;
	else paraLabel = parameterLabel;
	if (!addLabels) {
		roiManager("show all with labels");
		run("Flatten"); /* creates an RGB copy of the image with color coded objects or not */
	}
	else {
		roiManager("Show All without labels");
		/* Now to add scaled object labels */
		/* First: set default label settings */
		outlierStrokePC = 9; /* default outline stroke: % of font size */
		outlineStrokePC = 6; /* default outline stroke: % of font size */
		shadowDropPC = 10;  /* default outer shadow drop: % of font size */
		dIShOPC = 4; /* default inner shadow drop: % of font size */
		offsetX = maxOf(1, round(imageWidth/150)); /* default offset of label from edge */
		offsetY = maxOf(1, round(imageHeight/150)); /* default offset of label from edge */
		fontColor = "white";
		outlineColor = "black"; 	
		paraLabFontSize = round((imageHeight+imageWidth)/45);
		if ((paraLabFontSize<10) && acceptMinFontSize) paraLabFontSize = 10;
		statsLabFontSize = round((imageHeight+imageWidth)/60);
		if ((statsLabFontSize<10) && acceptMinFontSize) statsLabFontSize = 10;
		/* Feature Label Formatting Options Dialog . . . */
		Dialog.create("Feature Label Formatting Options");
			Dialog.setInsets(0, 150, 6);
			Dialog.addCheckbox("Add feature labels to each ROI?", true);
			allGrays = newArray("white", "black", "off-white", "off-black", "light_gray", "gray", "dark_gray");
			if (lut!="Grays")
				colorChoice = Array.concat(allGrays,allColors);
			else colorChoice = allGrays;
			Dialog.addChoice("Object label color:", colorChoice, colorChoice[0]);
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
			if (outlierChoice!="No") {	
				Dialog.setInsets(0, 0, 8);
				Dialog.addChoice("Outlier outline color:", allColors, allColors[0]);
				Dialog.addNumber("Outlier object outline stroke:", outlierStrokePC,0,3,"% of auto font size");
			}
			Dialog.addChoice("Decimal places:", newArray("Auto", "Manual", "Scientific", "0", "1", "2"), dpChoice); /* reuse previous dpChoice as default */
			Dialog.addNumber("Label outline stroke:", outlineStrokePC,0,3,"% of auto mean size");
			Dialog.addChoice("Label Outline (background) color:", colorChoice, colorChoice[1]);
			if (menuLimit > 796){
				Dialog.addNumber("Shadow drop: "+fromCharCode(0x00B1), shadowDropPC,0,3,"% of mean font size");
				Dialog.addNumber("Shadow displacement Right: "+fromCharCode(0x00B1), shadowDropPC,0,3,"% of mean font size");
				Dialog.addNumber("Shadow Gaussian blur:", floor(0.75 * shadowDropPC),0,3,"% of mean font size");
				Dialog.addNumber("Shadow darkness \(darkest = 100%\):", 50,0,3,"%, neg.= glow");
				Dialog.addNumber("Inner shadow drop: "+fromCharCode(0x00B1), dIShOPC,0,3,"% of min font size");
				Dialog.addNumber("Inner displacement right: "+fromCharCode(0x00B1), dIShOPC,0,3,"% of min font size");
				Dialog.addNumber("Inner shadow mean blur:",floor(dIShOPC/2),1,2,"pixels");
				Dialog.addNumber("Inner shadow darkness \(darkest = 100%\):", 15,0,3,"%");
			}
			else Dialog.addCheckbox("Tweak label format?", false);
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
			Dialog.addCheckbox("Add Parameter Label Title \("+paraLabel+"\)?", true);
			Dialog.addCheckbox("Add Summary Table", true);
			if (selectionExists) paraLocChoice = newArray("Current Selection", "Top Left", "Top Right", "Center", "Bottom Left", "Bottom Right", "Center of New Selection");
			else paraLocChoice = newArray("Top Left", "Top Right", "Center", "Bottom Left", "Bottom Right", "Center of New Selection"); 
			Dialog.addChoice("Title and Summary table Location:", paraLocChoice, paraLocChoice[0]);
			if (menuLimit > 752)	Dialog.addNumber("How many rows in table?", 12, 0, 2, "");
			else Dialog.addNumber("How many rows in table?", 6, 0, 2, "");
		Dialog.show();
			addLabels = Dialog.getCheckbox;
			fontColor = Dialog.getChoice(); /* Object label color */
			fontSCorrection =  Dialog.getNumber()/100;
			minLFontS = Dialog.getNumber();
			maxLFontS = Dialog.getNumber(); 
			fontStyle = Dialog.getChoice();
			fontName = Dialog.getChoice();
			if (outlierChoice!="No") {
				outlierColor = Dialog.getChoice(); /* Outlier object outline color */
				outlierStrokePC = Dialog.getNumber(); /* Outlier object outline thickness */
			}
			dpChoice = Dialog.getChoice();
			outlineStrokePC = Dialog.getNumber();
			outlineColor = Dialog.getChoice();
			if (menuLimit > 800){
				shadowDrop = Dialog.getNumber();
				shadowDisp = Dialog.getNumber();
				shadowBlur = Dialog.getNumber();
				shadowDarkness = Dialog.getNumber();
				innerShadowDrop = Dialog.getNumber();
				innerShadowDisp = Dialog.getNumber();
				innerShadowBlur = Dialog.getNumber();
				innerShadowDarkness = Dialog.getNumber();
				tweakLabels = false;
			}
			else tweakLabels = Dialog.getCheckbox();
			ctrChoice = Dialog.getChoice(); /* Choose ROI or morphological centers for object labels */
			paraLabAdd = Dialog.getCheckbox();
			summaryAdd = Dialog.getCheckbox();
			paraLabPos = Dialog.getChoice(); /* Parameter Label Position */
			statsChoiceLines = Dialog.getNumber();
			if (menuLimit <= 796){
				if (tweakLabels){
					Dialog.create("Label tweak options for low resolution monitors");
					Dialog.addNumber("Shadow drop: "+fromCharCode(0x00B1), shadowDropPC,0,3,"% of mean font size");
					Dialog.addNumber("Shadow displacement Right: "+fromCharCode(0x00B1), shadowDropPC,0,3,"% of mean font size");
					Dialog.addNumber("Shadow Gaussian blur:", floor(0.75 * shadowDropPC),0,3,"% of mean font size");
					Dialog.addNumber("Shadow darkness \(darkest = 100%\):", 50,0,3,"%, neg.= glow");
					Dialog.addNumber("Inner shadow drop: "+fromCharCode(0x00B1), dIShOPC,0,3,"% of min font size");
					Dialog.addNumber("Inner displacement right: "+fromCharCode(0x00B1), dIShOPC,0,3,"% of min font size");
					Dialog.addNumber("Inner shadow mean blur:",floor(dIShOPC/2),1,2,"pixels");
					Dialog.addNumber("Inner shadow darkness \(darkest = 100%\):",15,0,3,"%");
					Dialog.show();
					shadowDrop = Dialog.getNumber();
					shadowDisp = Dialog.getNumber();
					shadowBlur = Dialog.getNumber();
					shadowDarkness = Dialog.getNumber();
					innerShadowDrop = Dialog.getNumber();
					innerShadowDisp = Dialog.getNumber();
					innerShadowBlur = Dialog.getNumber();
					innerShadowDarkness = Dialog.getNumber();
				}
				else {  /* set the default values if no tweaking and lo-res monitor */
					shadowDrop = shadowDropPC;
					shadowDisp = shadowDropPC;
					shadowBlur = 0.75 * shadowDropPC;
					shadowDarkness = 50;
					innerShadowDrop = dIShOPC;
					innerShadowDisp = dIShOPC;
					innerShadowBlur = floor(dIShOPC/2);
					innerShadowDarkness = 15;
				}
			}
			if (isNaN(getResult("mc_X\(px\)",0)) && (ctrChoice=="Morphological Center")) AddMCsToResultsTable ();
		selectWindow(t);
		if (dpChoice=="Manual") 
			decPlaces = getNumber("Choose Number of Decimal Places", decPlaces);
		else if (dpChoice=="Scientific")
			decPlaces = -1;
		else if (dpChoice!="Auto")
			decPlaces = dpChoice;
		if (fontStyle=="unstyled") fontStyle="";
		if (stroke>=0) {
			run("Flatten"); /* Flatten converts to RGB so . . .  */
			rename(tN + "_" + parameterLabel + "_labels");
			if ((originalImageDepth==8) && (lut=="Grays")) run("8-bit"); /* restores gray if all gray settings */
		} else {
			run("Duplicate...", "title=labeled");
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
			setForegroundColorFromName(outlierColor);
			outlierStroke = maxOf(1,round(fontSize/100 * outlierStrokePC));
			run("Line Width...", "line=&outlierStroke");
			outlierCounter = 0;
			for (i=0; i<items; i++) {
				roiManager("select", i);
				if (outlierChoice=="Ramp_Range") {
					if (values[i]<rampMin || values[i]>rampMax) {
						run("Draw", "slice");
						outlierCounter +=1;
					}
				}
				else if (outlierChoice=="Manual_Input") {
					if (values[i]<outlierMin || values[i]>outlierMax) {
						run("Draw", "slice");
						outlierCounter +=1;
					}
				}
				else if (sigmaR>=1) {
					if (statsRampLines=="Ln") {
						if (values[i]<(expLnMeanMinusSDs[sigmaR]) || values[i]>(expLnMeanPlusSDs[sigmaR])) {
							run("Draw", "slice");
							outlierCounter +=1;
						}
					}
					else if (values[i]<(meanMinusSDs[sigmaR]) || values[i]>(meanPlusSDs[sigmaR])) {
						run("Draw", "slice");
						outlierCounter +=1;
					}
				}
				else { outlierChoice = "No"; i = items;} /* there seems to be a coding malfunction */
			}
			run("Line Width...", "line=1"); /* Reset line width to ImageJ default */
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
				labelValue = values[i];
				if (dpChoice=="Auto")
					decPlaces = autoCalculateDecPlaces4(labelValue,rampMin,rampMax,numLabels);
				labelString = d2s(labelValue,decPlaces); /* Reduce decimal places for labeling (move these two lines to below the labels you prefer) */
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
			if (innerShadowDrop<0) labelInnerShadowDrop = round(innerShadowDrop * negAdj);
			else labelInnerShadowDrop = innerShadowDrop;
			if (innerShadowDisp<0) labelInnerShadowDisp = round(innerShadowDisp * negAdj);
			else labelInnerShadowDisp = innerShadowDisp;
			if (innerShadowBlur<0) labelInnerShadowBlur = round(innerShadowBlur * negAdj);
			else labelInnerShadowBlur = innerShadowBlur;
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
			objectLabelInnerShadowDrop = floor(minFontFactor * labelInnerShadowDrop);
			objectLabelInnerShadowDisp = floor(minFontFactor * labelInnerShadowDisp);
			objectLabelInnerShadowBlur = floor(minFontFactor * labelInnerShadowBlur);
			run("Select None");
			roiManager("show none");
			fancyTextOverImage(objectLabelShadowDrop,objectLabelShadowDisp,objectLabelShadowBlur,shadowDarkness,objectOutlineStroke,objectLabelInnerShadowDrop,objectLabelInnerShadowDisp,objectLabelInnerShadowBlur,innerShadowDarkness); /* requires "textImage" and original workingImage */
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
		summaryDP = decPlaces + 2;
		outlierChoiceAbbrev = cleanLabel(outlierChoice);
		if (outlierChoice=="Manual_Input") 	outlierChoiceAbbrev = "<" + outlierMin + " >" + outlierMax + " " + unitLabel;
		else if (outlierChoice=="Ramp_Range") 	outlierChoiceAbbrev = "<" + rampMin + " >" + rampMax + " " + unitLabel;
		else outlierChoiceAbbrev = "" + fromCharCode(0x2265) + outlierChoiceAbbrev;
		arrayMean = d2s(arrayMean,summaryDP);
		coeffVar = d2s((100/arrayMean)*arraySD,summaryDP);
		arraySD = d2s(arraySD,summaryDP);
		arrayMin = d2s(arrayMin,summaryDP);
		arrayMax = d2s(arrayMax,summaryDP);
		median = d2s(arrayQuartile[1],summaryDP);
		if (IQR!=0) mode = d2s(mode,summaryDP);
	}

	if (summaryAdd || paraLabAdd) {
		/* Then Statistics Summary Options Dialog . . . */
		Dialog.create("Statistics Summary Options");
			if (paraLabAdd) {
				Dialog.addString("Parameter Label or Title:",paraLabel,12);
				Dialog.addNumber("Parameter label font size:", paraLabFontSize);	
			}
			if (!summaryAdd) Dialog.addNumber("Optional text font size:", statsLabFontSize);
			else {
				Dialog.addNumber("Statistics summary font size:", statsLabFontSize);
				Dialog.addNumber("Change decimal places from " + summaryDP + ": ", summaryDP);
				statsChoice1 = newArray("None", "Dashed Line:  ---", "Number of objects:  " + items);
				if (outlierChoice!="No") statsChoice2 = newArray("Outlines:  " + outlierCounter + " objects " + outlierChoiceAbbrev + " in " + outlierColor);
				statsChoice3 = newArray(			
				"Mean:  " + arrayMean + " " +unitLabel,
				"Median:  " + median + " " +unitLabel,
				"StdDev:  " + arraySD + " " +unitLabel,
				"CoeffVar:  " + coeffVar + "%", "Min-Max:  " + arrayMin + " - " + arrayMax + " " +unitLabel,
				"Minimum:  " + arrayMin, "Maximum:  " + arrayMax);
				statsChoice4 = newArray(	/* additional frequency distribution stats */		
				"Mode:  " + mode + " " + unitLabel + " \(W = " +autoDistW+ "\)",
				"InterQuartile Range:  " + IQR + " " + unitLabel);
				statsChoice5 = newArray(  /* log stats */
				"ln Stats Mean:  " + d2s(expLnMeanPlusSDs[0],summaryDP) + " " +unitLabel,
				"ln Stats +SD:  " + d2s((expLnMeanPlusSDs[1]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel,
				"ln Stats +2SD:  " + d2s((expLnMeanPlusSDs[2]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel,
				"ln Stats +3SD:  " + d2s((expLnMeanPlusSDs[3]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel,
				"ln Stats -SD:  " + d2s((expLnMeanMinusSDs[1]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel,
				"ln Stats -2SD:  " + d2s((expLnMeanMinusSDs[2]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel,
				"ln Stats -3SD:  " + d2s((expLnMeanMinusSDs[3]-expLnMeanPlusSDs[0]),summaryDP) + " " +unitLabel);
				statsChoice6 = newArray(
				"Pixel Size:  " + lcf + " " + unit, "Image Title:  " + titleAbbrev, "Manual",
				"Long Underline:  ___","Blank line");
				if ((IQR!=0) && freqDistRamp) statsChoice3 = Array.concat(statsChoice3,statsChoice4);
				if (outlierChoice!="No") statsChoice = Array.concat(statsChoice1,statsChoice2,statsChoice3,statsChoice5,statsChoice6);
				else statsChoice = Array.concat(statsChoice1,statsChoice3,statsChoice5,statsChoice6);
				for (i=0; i<statsChoiceLines; i++) {
					if (i<6) Dialog.addChoice("Statistics label line "+(i+1)+":", statsChoice, statsChoice[i+2]);
					else Dialog.addChoice("Statistics label line "+(i+1)+":", statsChoice, statsChoice[0]);
				}
				if (menuLimit > 752)	textChoiceLines = 3;
				else textChoiceLines = 1;
				userInput = newArray(textChoiceLines);
				for (i=0; i<textChoiceLines; i++)
					Dialog.addString("Manual: Line selected above: "+(i+1)+":","None", 30);
			}	
			Dialog.addChoice("Summary and parameter font color:", colorChoice, "white");
			Dialog.addChoice("Summary and parameter outline color:", colorChoice, "black");
			if (menuLimit>=796) { /* room to show full dialog */
				Dialog.addNumber("Outline stroke:", outlineStrokePC,0,3,"% of summary font size");
				Dialog.addNumber("Shadow drop: ±", shadowDropPC,0,3,"% of summary font size");
				Dialog.addNumber("Shadow displacement Right: ±", shadowDropPC,0,3,"% of summary font size");
				Dialog.addNumber("Shadow Gaussian blur:", floor(0.75 * shadowDropPC),0,3,"% of summary font size");
				Dialog.addNumber("Shadow darkness \(darkest = 100\):",50,0,3,"%, neg.= glow");
				Dialog.addNumber("Inner shadow drop: ±", dIShOPC,0,3,"% of summary font size");
				Dialog.addNumber("Inner displacement right: ±", dIShOPC,0,3,"% of summary font size");
				Dialog.addNumber("Inner shadow mean blur:",floor(dIShOPC/2),1,2,"pixels");
				Dialog.addNumber("Inner shadow darkness \(darkest = 100%\):", 20,0,3,"%");
				Dialog.show();
			}
			else Dialog.addCheckbox("Tweak summary format?",false);
			// else Dialog.show(); /* Sorry, only an abbreviated menu for small screens */
			
			if (paraLabAdd) {
				paraLabel = Dialog.getString();
				paraLabFontSize =  Dialog.getNumber();
			}
			statsLabFontSize =  Dialog.getNumber();
			if (summaryAdd) {
				newSummaryDP = Dialog.getNumber;
				statsLabLine = newArray(statsChoiceLines);
				for (i=0; i<statsChoiceLines; i++)
					statsLabLine[i] = Dialog.getChoice();
				textInputLines = newArray(textChoiceLines);
				for (i=0; i<textChoiceLines; i++)
					textInputLines[i] = Dialog.getString();
			}
			fontColor = Dialog.getChoice();
			outlineColor = Dialog.getChoice();
			if (menuLimit>=796) {
				outlineStrokePC = Dialog.getNumber();
				shadowDrop = Dialog.getNumber();
				shadowDisp = Dialog.getNumber();
				shadowBlur = Dialog.getNumber();
				textLabelShadowDarkness = Dialog.getNumber();
				innerShadowDrop = Dialog.getNumber();
				innerShadowDisp = Dialog.getNumber();
				innerShadowBlur = Dialog.getNumber();
				textLabelInnerShadowDarkness = Dialog.getNumber();
			}
			else if (Dialog.getCheckbox){
				Dialog.create("Statistics Summary Options Tweaks");
				Dialog.addNumber("Outline stroke:", outlineStrokePC,0,3,"% of stats label font size");
				Dialog.addNumber("Shadow drop: ±", shadowDropPC,0,3,"% of stats label font size");
				Dialog.addNumber("Shadow displacement Right: ±", shadowDropPC,0,3,"% of stats label font size");
				Dialog.addNumber("Shadow Gaussian blur:", floor(0.75 * shadowDropPC),0,3,"% of stats label font size");
				Dialog.addNumber("Shadow darkness \(darkest = 100\):",50,0,3,"%, neg.= glow");
				Dialog.addNumber("Inner shadow drop: ±", dIShOPC,0,3,"% of stats label font size");
				Dialog.addNumber("Inner displacement right: ±", dIShOPC,0,3,"% of stats label font size");
				Dialog.addNumber("Inner shadow mean blur:",floor(dIShOPC/2),1,2,"pixels");
				Dialog.addNumber("Inner shadow darkness \(darkest = 100%\):",20,0,3,"%");
				Dialog.show();
				outlineStrokePC = Dialog.getNumber();
				shadowDrop = Dialog.getNumber();
				shadowDisp = Dialog.getNumber();
				shadowBlur = Dialog.getNumber();
				shadowDarkness = Dialog.getNumber();
				innerShadowDrop = Dialog.getNumber();
				innerShadowDisp = Dialog.getNumber();
				innerShadowBlur = Dialog.getNumber();
				innerShadowDarkness = Dialog.getNumber();
			}
			else {
				outlineStrokePC = outlineStrokePC;
				shadowDrop = shadowDropPC;
				shadowDisp = shadowDropPC;
				shadowBlur = floor(0.75 * shadowDropPC);
				shadowDarkness = 50;
				innerShadowDrop = dIShOPC;
				innerShadowDisp = dIShOPC;
				innerShadowBlur = floor(dIShOPC/2);
				innerShadowDarkness = 20;
			}
		/* End optional parameter label dialog */
		if (shadowDrop<0) summLabelShadowDrop = round(shadowDrop * negAdj);
		else textLabelShadowDrop = shadowDrop;
		if (shadowDisp<0) textLabelShadowDisp = round(shadowDisp * negAdj);
		else textLabelShadowDisp = shadowDisp;
		if (shadowBlur<0) textLabelShadowBlur = round(shadowBlur *negAdj);
		else textLabelShadowBlur = shadowBlur;
		if (innerShadowDrop<0) textLabelInnerShadowDrop = round(innerShadowDrop * negAdj);
		else textLabelInnerShadowDrop = innerShadowDrop;
		if (innerShadowDisp<0) textLabelInnerShadowDisp = round(innerShadowDisp * negAdj);
		else textLabelInnerShadowDisp = innerShadowDisp;
		if (innerShadowBlur<0) textLabelInnerShadowBlur = round(innerShadowBlur * negAdj);
		else textLabelInnerShadowBlur = innerShadowBlur;
		/* convert font percentages to pixels */
		fontFactor = statsLabFontSize/100;
		outlineStroke = round(fontFactor * outlineStrokePC);
		textLabelShadowDrop = floor(fontFactor * textLabelShadowDrop);
		textLabelShadowDisp = floor(fontFactor * textLabelShadowDisp);
		textLabelShadowBlur = floor(fontFactor * textLabelShadowBlur);
		textLabelInnerShadowDrop = floor(fontFactor * textLabelInnerShadowDrop);
		textLabelInnerShadowDisp = floor(fontFactor * textLabelInnerShadowDisp);
		textLabelInnerShadowBlur = floor(fontFactor * textLabelInnerShadowBlur);
		paraOutlineStroke = outlineStroke * paraLabFontSize/minLFontS;
		/*
		Count lines of summary label */
		if (paraLabAdd) labLines = 1;
		else labLines = 0;
		if (summaryAdd) {
			if (newSummaryDP!=summaryDP) {
				summaryDP = newSummaryDP;
				arrayMean = d2s(arrayMean,summaryDP);
				coeffVar = d2s((100/arrayMean)*arraySD,summaryDP);
				arraySD = d2s(arraySD,summaryDP);
				arrayMin = d2s(arrayMin,summaryDP);
				arrayMax = d2s(arrayMax,summaryDP);
				median = d2s(arrayQuartile[1],summaryDP);
				if (IQR!=0) mode = d2s(mode,summaryDP);
			}
			statsLines = 0;
			statsLabLineText = newArray(statsChoiceLines);
			setFont(fontName, statsLabFontSize, fontStyle);
			longestStringWidth = 0;
			userTextLine=0;
			if (lengthOf(t)>round(imageWidth/(1.5*fontSize)))
				titleShort = substring(t, 0, round(imageWidth/(1.5*fontSize))) + "...";
			else titleShort = t;
			for (i=0; i<statsLabLineText.length; i++) {
				if (statsLabLine[i]!="None") {
					statsLines = i + 1;
					if (indexOf(statsLabLine[i], ":  ")>0) statsLabLine[i] = substring(statsLabLine[i], 0, indexOf(statsLabLine[i], ":  "));
					if (statsLabLine[i]=="Dashed Line:  ---") statsLabLineText[i] = "----------";
					else if (statsLabLine[i]=="Number of objects") statsLabLineText[i] = "Objects = " + items;
					else if (statsLabLine[i]=="Outlines") statsLabLineText[i] = "Outlines:  " + outlierCounter + " objects " + outlierChoiceAbbrev + " in " + outlierColor;
					else if (statsLabLine[i]=="Mean") statsLabLineText[i] = "Mean = " + arrayMean + " " + unitLabel;
					else if (statsLabLine[i]=="Median") statsLabLineText[i] = "Median = " + median + " " + unitLabel;
					else if (statsLabLine[i]=="StdDev") statsLabLineText[i] = "Std.Dev.: " + arraySD + " " + unitLabel;
					else if (statsLabLine[i]=="CoeffVar") statsLabLineText[i] = "Coeff.Var.: " + coeffVar + "%";
					else if (statsLabLine[i]=="Min-Max") statsLabLineText[i] = "Range: " + arrayMin + " - " + arrayMax + " " + unitLabel;
					else if (statsLabLine[i]=="Minimum") statsLabLineText[i] = "Minimum: " + arrayMin + " " + unitLabel;
					else if (statsLabLine[i]=="Maximum") statsLabLineText[i] = "Maximum: " + arrayMax + " " + unitLabel;
					else if (statsLabLine[i]=="Mode") statsLabLineText[i] = "Mode = " + mode + " " + unitLabel + " \(W = " +autoDistW+ "\)";
					else if (statsLabLine[i]=="InterQuartile Range") statsLabLineText[i] = "InterQuartile Range = " + IQR + " " +unitLabel;
					else if (statsLabLine[i]=="ln Stats Mean") statsLabLineText[i] = "ln Stats Mean: " + d2s(expLnMeanPlusSDs[0],summaryDP) + " " + unitLabel;
					else if (statsLabLine[i]=="ln Stats +SD") statsLabLineText[i] = "ln Stats +SD: " + d2s((expLnMeanPlusSDs[1]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
					else if (statsLabLine[i]=="ln Stats +2SD") statsLabLineText[i] = "ln Stats +2SD: " + d2s((expLnMeanPlusSDs[2]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
					else if (statsLabLine[i]=="ln Stats +3SD") statsLabLineText[i] = "ln Stats +3SD: " + d2s((expLnMeanPlusSDs[3]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
					else if (statsLabLine[i]=="ln Stats -SD") statsLabLineText[i] = "ln Stats -SD: " + d2s((expLnMeanMinusSDs[1]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
					else if (statsLabLine[i]=="ln Stats +2SD") statsLabLineText[i] = "ln Stats -2SD: " + d2s((expLnMeanMinusSDs[2]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
					else if (statsLabLine[i]=="ln Stats +3SD") statsLabLineText[i] = "ln Stats -3SD: " + d2s((expLnMeanMinusSDs[3]-expLnMeanPlusSDs[0]),summaryDP) + " " + unitLabel;
					else if (statsLabLine[i]=="Pixel Size") statsLabLineText[i] = "Scale: 1 pixel = " + lcf + " " + unit;
					else if (statsLabLine[i]=="Image Title") statsLabLineText[i] = "Image: " + titleShort;
					else if (statsLabLine[i]=="Manual"){
						 if (textInputLines[userTextLine]!="None") statsLabLineText[i] = textInputLines[userTextLine];
						 else statsLabLineText[i] = "";
						 userTextLine += 1;
					}
					else if (statsLabLine[i]=="Long Underline") statsLabLineText[i] = "__________";
					else if (statsLabLine[i]=="Blank line") statsLabLineText[i] = " ";
					if (getStringWidth(statsLabLineText[i])>longestStringWidth) longestStringWidth = getStringWidth(statsLabLineText[i]);
				}
			}
			linesSpace = 1.2 * ((labLines*paraLabFontSize)+(statsLines*statsLabFontSize));
		}
		if (paraLabAdd && !summaryAdd) longestStringWidth = getStringWidth(paraLabel);
		if (paraLabAdd) {
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
			} else if (paraLabPos == "Center of New Selection"){
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
					fontFactor = fontSize/100;
					if (paraOutlineStroke>1) paraOutlineStroke = maxOf(1,round(fontFactor * paraOutlineStroke));
					else outlineStroke = round(fontFactor * outlineStroke);
					if (textLabelShadowDrop>1) textLabelShadowDrop = maxOf(1,round(fontFactor * textLabelShadowDrop));
					else textLabelShadowDrop = round(fontFactor * textLabelShadowDrop);
					if (textLabelShadowDisp>1) textLabelShadowDisp = maxOf(1,round(fontFactor * textLabelShadowDisp));
					else textLabelShadowDisp = round(fontFactor * textLabelShadowDisp);
					if (textLabelShadowBlur>1) textLabelShadowBlur = maxOf(1,round(fontFactor * textLabelShadowBlur));
					else textLabelShadowBlur = round(fontFactor * textLabelShadowBlur);
					textLabelInnerShadowDrop = floor(fontFactor * textLabelInnerShadowDrop);
					textLabelInnerShadowDisp = floor(fontFactor * textLabelInnerShadowDisp);
					textLabelInnerShadowBlur = floor(fontFactor * textLabelInnerShadowBlur);
				}
				posStartX = posStartX + round((posWidth/2) - longestStringWidth/2);
				posStartY = posStartY + round((posHeight/2) - (linesSpace/2) + fontSize);
				if (just=="auto") {
					if (posStartX<imageWidth*0.4) just = "left";
					else if (posStartX>imageWidth*0.6) just = "right";
					else just = "center";
				}
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
		/* Draw summary over top of object labels */
		if (is("Batch Mode")==false) setBatchMode(true);	/* toggle batch mode back on */
		textImages = newArray("textImage","antiAliased");
		/* Create Label Mask */
		newImage("textImage", "8-bit black", imageWidth, imageHeight, 1);
		roiManager("deselect");
		run("Select None");
		if (paraLabFontSize>=0) {
			setFont(fontName,paraLabFontSize, fontStyle);
			newImage("antiAliased", originalImageDepth, imageWidth, imageHeight, 1);
			/* Draw text for mask and antiAliased tweak */
			/* determine font color intensities settings for antialiased tweak */
			fontColorArray = getColorArrayFromColorName(fontColor);
			Array.getStatistics(fontColorArray,fontIntMean);
			fontInt = floor(fontIntMean);
			outlineColorArray = getColorArrayFromColorName(outlineColor);
			Array.getStatistics(outlineColorArray,outlineIntMean);
			outlineInt = floor(outlineIntMean);
			paraLabelY1 = paraLabelY;
			for (t=0; t<2; t++) {
				selectWindow(textImages[t]);
				if (t==0) setColor("white");
				else {
					paraLabelY = paraLabelY1;
					run("Select All");
					setColorFromColorName(outlineColor);
					fill();
					roiManager("deselect");
					run("Select None");
					setColorFromColorName(fontColor);
				}
				if (paraLabAdd) {
					setFont(fontName,paraLabFontSize, fontStyle);
					if (just=="left") drawString(paraLabel, paraLabelX, paraLabelY);
					else if (just=="right") drawString(paraLabel, paraLabelX + (longestStringWidth - getStringWidth(paraLabel)), paraLabelY);
					else drawString(paraLabel, paraLabelX + (longestStringWidth-getStringWidth(paraLabel))/2, paraLabelY);
					paraLabelY += round(1.2 * paraLabFontSize);
				}
				if (summaryAdd) {
					setFont(fontName,statsLabFontSize, fontStyle);
					for (i=0; i<statsLines; i++) {
						if (just=="left") drawString(statsLabLineText[i], paraLabelX, paraLabelY);
						else if (just=="right") drawString(statsLabLineText[i], paraLabelX + (longestStringWidth - getStringWidth(statsLabLineText[i])), paraLabelY);
						else drawString(statsLabLineText[i], paraLabelX + (longestStringWidth-getStringWidth(statsLabLineText[i]))/2, paraLabelY);
						paraLabelY += round(1.2 * statsLabFontSize);		
					}
				}
			}
			fancyTextOverImage(textLabelShadowDrop,textLabelShadowDisp,textLabelShadowBlur,shadowDarkness,outlineStroke,textLabelInnerShadowDrop,textLabelInnerShadowDisp,textLabelInnerShadowBlur,innerShadowDarkness); /* requires "textImage" and original "workingImage" */
			
			if (isOpen("antiAliased")) {
				if (fontInt>=outlineInt){
					imageCalculator("Max","textImage","antiAliased");
					imageCalculator("Min",workingImage,"textImage");
				}
				else {
					imageCalculator("Max","textImage","antiAliased");
					imageCalculator("Min",workingImage,"textImage");
				}
			}		
			closeImageByTitle("textImage");
			closeImageByTitle("label_mask");
			closeImageByTitle("antiAliased");
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
		rename(tN + "_" + parameterLabel + "\+coded");
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
				run("Select None");
				if (createCombo=="Combine Scaled Ramp with New Manual Crop of Image") {
					setTool("rectangle");
					title="Crop Location for Combined Image";
					msg = "Select the Crop Area";
					waitForUser(title, msg);
					run("Crop");
					run("Select None");
				}
				else {
					run("Select Bounding Box (guess background color)");
					run("Enlarge...", "enlarge=" + round(imageHeight*0.02) + " pixel"); /* Adds a 2% margin */
					run("Crop");
				}
				croppedImageHeight = getHeight(); croppedImageWidth = getWidth();
				if (is("Batch Mode")==false) setBatchMode(true);	/* toggle batch mode back on */
				selectWindow(tR);
				rampScale = croppedImageHeight/canvasH;
				run("Scale...", "x=&rampScale y=&rampScale interpolation=Bicubic average create title=scaled_ramp");
				canvasH = getHeight(); /* update ramp height */
				srW = getWidth + maxOf(2,croppedImageWidth/500);
				comboW = srW + croppedImageWidth + maxOf(2,croppedImageWidth/500);
				selectWindow("tempCrop");
				run("Canvas Size...", "width=&comboW height=&croppedImageHeight position=Top-Left");
				makeRectangle(croppedImageWidth + maxOf(2,croppedImageWidth/500), round((croppedImageHeight-canvasH)/2), srW, croppedImageHeight);
				run("Image to Selection...", "image=scaled_ramp opacity=100");
				run("Flatten");
				if (originalImageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
				rename(tNC + "_crop+ramp");
				closeImageByTitle("scaled_ramp");
				closeImageByTitle("temp_combo");	
				closeImageByTitle("tempCrop");				
			}
			else {
				selectWindow(tR);
				if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Scaled Ramp with New Image") {
					rampScale = imageHeight/canvasH;
					run("Scale...", "x=&rampScale y=&rampScale interpolation=Bicubic average create title=scaled_ramp");
					canvasH = getHeight(); /* update ramp height */
				}
				srW = getWidth + maxOf(2,imageWidth/500);
				comboW = srW + imageWidth + maxOf(2,imageWidth/500);
				selectWindow(tNC);
				if (createCombo=="Combine Scaled Ramp with New Image" || createCombo=="Combine Ramp with New Image") run("Duplicate...", "title=temp_combo");
				run("Canvas Size...", "width=&comboW height=&imageHeight position=Top-Left");
				makeRectangle(imageWidth + maxOf(2,imageWidth/500), round((imageHeight-canvasH)/2), srW, imageHeight);
				if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Scaled Ramp with New Image")
					run("Image to Selection...", "image=scaled_ramp opacity=100");
				else run("Image to Selection...", "image=&tR opacity=100"); /* can use "else" here because we have already eliminated the "No" option */
				run("Flatten");
				if (originalImageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
				rename(tNC + "+ramp");
				closeImageByTitle("scaled_ramp");
				closeImageByTitle("temp_combo");
				if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Ramp with Current") closeImageByTitle(tNC);
			}
		}
	}
	if (selectionExists) makeRectangle(selPosStartX, selPosStartY, originalSelEWidth, originalSelEHeight);
	setBatchMode("exit & display");
	restoreSettings;
	memFlush(200);
	showStatus("ROI Color Coder with Scaled Labels and Summary Macro Finished");
	beep(); wait(300); beep(); wait(300); beep();
}
	/*
		   ( 8(|)	( 8(|)	Functions	@@@@@:-)	@@@@@:-)
   */
	function AddMCsToResultsTable () {
	/* 	Based on "MCentroids.txt" Morphological centroids by thinning assumes white particles: G. Landini
		http://imagejdocu.tudor.lu/doku.php?id=plugin:morphology:morphological_operators_for_imagej:start
		http://www.mecourse.com/landinig/software/software.html
		Modified to add coordinates to Results Table: Peter J. Lee NHMFL  7/20-29/2016
		v180102	Fixed typos and updated functions.
		v180104 Removed unnecessary changes to settings.
		v180312 Add minimum and maximum morphological radii.
		v180602 Add 0.5 pixels to output co-ordinates to match X,Y, XM and YM system for ImageJ results
		v190802 Updated distance measurement to use more compact pow function.
	*/
		workingTitle = getTitle();
		if (!checkForPlugin("morphology_collection")) restoreExit("Exiting: Gabriel Landini's morphology suite is needed to run this function.");
		binaryCheck(workingTitle); /* Makes sure image is binary and sets to white background, black objects */
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
		run("Collect Garbage"); 
	}
 	function autoCalculateDecPlaces4(dP,min,max,numberOfLabels){
		/* v180316 4 variable version */
		step = (max-min)/numberOfLabels;
		stepSci = d2s(step, -1);
		iExp = indexOf(stepSci, "E");
		stepExp = parseInt(substring(stepSci, iExp+1));
		if (stepExp<0)	dP = -1*stepExp+1;
		if (stepExp<-7) dP = -1; /* Scientific Notation */
		if (stepExp>=0) dP = 1;
		if (stepExp>=2) dP = 0;
		if (stepExp>=5) dP = -1; /* Scientific Notation */
		return dP;
	}
	function autoCropGuessBackgroundSafe() {
		if (is("Batch Mode")==true) setBatchMode(false);	/* toggle batch mode off */
		run("Auto Crop (guess background color)"); /* not reliable in batch mode */
		if (is("Batch Mode")==false) setBatchMode(true);	/* toggle batch mode back on */
	}	
	function binaryCheck(windowTitle) { /* For black objects on a white background */
		/* v180601 added choice to invert or not */
		/* v180907 added choice to revert to the true LUT, changed border pixel check to array stats */
		selectWindow(windowTitle);
		if (is("binary")==0) run("8-bit");
		/* Quick-n-dirty threshold if not previously thresholded */
		getThreshold(t1,t2); 
		if (t1==-1)  {
			run("8-bit");
			run("Auto Threshold", "method=Default");
			run("Convert to Mask");
		}
		if (is("Inverting LUT")==true)  {
			trueLUT = getBoolean("The LUT appears to be inverted, do you want the true LUT?", "Yes Please", "No Thanks");
			if (trueLUT==true) run("Invert LUT");
		}
		/* Make sure black objects on white background for consistency */
		cornerPixels = newArray(getPixel(0, 0), getPixel(0, 1), getPixel(1, 0), getPixel(1, 1));
		Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
		if (cornerMax!=cornerMin) restoreExit("Problem with image border: Different pixel intensities at corners");
		/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
			i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
		if (cornerMean==0) {
			inversion = getBoolean("The background appears to have intensity zero, do you want the intensities inverted?", "Yes Please", "No Thanks");
			if (inversion==true) run("Invert"); 
		}
	}
	function checkForPlugin(pluginName) {
		/* v161102 changed to true-false
			v180831 some cleanup */
		var pluginCheck = false, subFolderCount = 0;
		if (getDirectory("plugins") == "") restoreExit("Failure to find any plugins!");
		else pluginDir = getDirectory("plugins");
		if (!endsWith(pluginName, ".jar")) pluginName = pluginName + ".jar";
		if (File.exists(pluginDir + pluginName)) {
				pluginCheck = true;
				showStatus(pluginName + "found in: "  + pluginDir);
		}
		else {
			pluginList = getFileList(pluginDir);
			subFolderList = newArray(lengthOf(pluginList));
			for (i=0; i<lengthOf(pluginList); i++) {
				if (endsWith(pluginList[i], "/")) {
					subFolderList[subFolderCount] = pluginList[i];
					subFolderCount += 1;
				}
			}
			subFolderList = Array.trim(subFolderList, subFolderCount);
			for (i=0; i<lengthOf(subFolderList); i++) {
				if (File.exists(pluginDir + subFolderList[i] +  "\\" + pluginName)) {
					pluginCheck = true;
					showStatus(pluginName + " found in: " + pluginDir + subFolderList[i]);
					i = lengthOf(subFolderList);
				}
			}
		}
		return pluginCheck;
	}
	function checkForPluginNameContains(pluginNamePart) {
		/* v180831 1st version to check for partial names so avoid versioning problems
			v181005 1st version that works correctly ? */
		var pluginCheck = false, subFolderCount = 0;
		if (getDirectory("plugins") == "") restoreExit("Failure to find any plugins!");
		else pluginDir = getDirectory("plugins");
		pluginList = getFileList(pluginDir);
		subFolderList = newArray(lengthOf(pluginList));
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
			subFolderList = newArray(0);
			for (i=0; i<lengthOf(pluginList); i++) {
				if (endsWith(pluginList[i], "/")) subFolderList = Array.concat(subFolderList, pluginList[i]);
			}
			for (i=0; i<lengthOf(subFolderList); i++) {
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
		nROIs = roiManager("count");
		nRes = nResults;
		if (nRes==0)	{
			Dialog.create("No Results to Work With");
			Dialog.addCheckbox("Run Analyze-particles to generate table?", true);
			Dialog.addMessage("This macro requires a Results table to analyze.\n \nThere are   " + nRes +"   results.\nThere are    " + nROIs +"   ROIs.");
			Dialog.show();
			analyzeNow = Dialog.getCheckbox(); /* If (analyzeNow==true), ImageJ Analyze Particles will be performed, otherwise exit */
			if (analyzeNow==true) {
				if (roiManager("count")!=0) {
					roiManager("deselect")
					roiManager("delete"); 
				}
				setOption("BlackBackground", false);
				run("Analyze Particles..."); /* Let user select settings */
			}
			else restoreExit("Goodbye, your previous setting will be restored.");
		}
	}
	function checkForRoiManager() {
		/* v161109 adds the return of the updated ROI count and also adds dialog if there are already entries just in case . .
			v180104 only asks about ROIs if there is a mismatch with the results
			v190628 adds option to import saved ROI set */
		nROIs = roiManager("count");
		nRes = nResults; /* Used to check for ROIs:Results mismatch */
		if(nROIs==0 || nROIs!=nRes){
			Dialog.create("ROI options");
				Dialog.addMessage("This macro requires that all objects have been loaded into the ROI manager.\n \nThere are   " + nRes +"   results.\nThere are   " + nROIs +"   ROIs.\nDo you want to:");
				if(nROIs==0) Dialog.addCheckbox("Import a saved ROI list",false);
				else Dialog.addCheckbox("Replace the current ROI list with a saved ROI list",false);
				if(nRes==0) Dialog.addCheckbox("Import a Results Table \(csv\) file",false);
				else Dialog.addCheckbox("Clear Results Table and import saved csv",false);
				Dialog.addCheckbox("Clear ROI list and Results Table and reanalyze \(overrides above selections\)",true);
				Dialog.addCheckbox("Get me out of here, I am having second thoughts . . .",false);
			Dialog.show();
				importROI = Dialog.getCheckbox;
				importResults = Dialog.getCheckbox;
				runAnalyze = Dialog.getCheckbox;
				if (Dialog.getCheckbox) restoreExit("Sorry this did not work out for you.");
			if (runAnalyze) {
				if (isOpen("ROI Manager"))	roiManager("reset");
				setOption("BlackBackground", false);
				if (isOpen("Results")) {
					selectWindow("Results");
					run("Close");
				}
				run("Analyze Particles..."); /* Let user select settings */
				if (nResults!=roiManager("count"))
					restoreExit("Results and ROI Manager counts do not match!");
			}
			else {
				if (importROI) {
					if (isOpen("ROI Manager"))	roiManager("reset");
					msg = "Import ROI set \(zip file\), click \"OK\" to continue to file chooser";
					showMessage(msg);
					roiManager("Open", "");
				}
				if (importResults){
					if (isOpen("Results")) {
						selectWindow("Results");
						run("Close");
					}
					msg = "Import Results Table, click \"OK\" to continue to file chooser";
					showMessage(msg);
					open("");
					Table.rename(Table.title, "Results");
				}
			}
		}
		nROIs = roiManager("count");
		nRes = nResults; /* Used to check for ROIs:Results mismatch */
		if(nROIs==0 || nROIs!=nRes)
			restoreExit("Goodbye, your previous setting will be restored.");
		return roiManager("count"); /* Returns the new count of entries */
	}
	function checkForUnits() {  /* Generic version 
		/* v161108 (adds inches to possible reasons for checking calibration)
		 v170914 Radio dialog with more information displayed */
		getPixelSize(unit, pixelWidth, pixelHeight);
		if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="" || unit=="inches"){
			Dialog.create("Suspicious Units");
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
		v180611 added "degreeC" */
		string= replace(string, "\\^2", fromCharCode(178)); /* superscript 2 */
		string= replace(string, "\\^3", fromCharCode(179)); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, "\\^-1", fromCharCode(0x207B) + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-2", fromCharCode(0x207B) + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "\\^-^1", fromCharCode(0x207B) + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-^2", fromCharCode(0x207B) + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "(?<![A-Za-z0-9])u(?=m)", fromCharCode(181)); /* micron units */
		string= replace(string, "\\b[aA]ngstrom\\b", fromCharCode(197)); /* Ångström unit symbol */
		string= replace(string, "  ", " "); /* Replace double spaces with single spaces */
		string= replace(string, "_", fromCharCode(0x2009)); /* Replace underlines with thin spaces */
		string= replace(string, "px", "pixels"); /* Expand pixel abbreviation */
		string= replace(string, "degreeC", fromCharCode(0x00B0) + "C"); /* Degree symbol for dialog boxes */
		string = replace(string, " " + fromCharCode(0x00B0), fromCharCode(0x2009) + fromCharCode(0x00B0)); /* Replace normal space before degree symbol with thin space */
		string= replace(string, " °", fromCharCode(0x2009) + fromCharCode(0x00B0)); /* Replace normal space before degree symbol with thin space */
		string= replace(string, "sigma", fromCharCode(0x03C3)); /* sigma for tight spaces */
		string= replace(string, "±", fromCharCode(0x00B1)); /* plus or minus */
		return string;
	}
	function closeImageByTitle(windowTitle) {  /* Cannot be used with tables */
		/* v181002 reselects original image at end if open */
		oIID = getImageID();
        if (isOpen(windowTitle)) {
			selectWindow(windowTitle);
			close();
		}
		if (isOpen(oIID)) selectImage(oIID);
	}
	function createInnerShadowFromMask4(iShadowDrop, iShadowDisp, iShadowBlur, iShadowDarkness) {
		/* Requires previous run of: originalImageDepth = bitDepth();
		because this version works with different bitDepths
		v161115 calls -4- variables: drop, displacement blur and darkness */
		showStatus("Creating inner shadow for labels . . . ");
		newImage("inner_shadow", "8-bit white", imageWidth, imageHeight, 1);
		getSelectionFromMask("label_mask");
		setBackgroundColor(0,0,0);
		run("Clear Outside");
		getSelectionBounds(selMaskX, selMaskY, selMaskWidth, selMaskHeight);
		setSelectionLocation(selMaskX-iShadowDisp, selMaskY-iShadowDrop);
		setBackgroundColor(0,0,0);
		run("Clear Outside");
		getSelectionFromMask("label_mask");
		expansion = abs(iShadowDisp) + abs(iShadowDrop) + abs(iShadowBlur);
		if (expansion>0) run("Enlarge...", "enlarge=[expansion] pixel");
		if (iShadowBlur>0) run("Gaussian Blur...", "sigma=[iShadowBlur]");
		run("Unsharp Mask...", "radius=0.5 mask=0.2"); /* A tweak to sharpen the effect for small font sizes */
		imageCalculator("Max", "inner_shadow","label_mask");
		run("Select None");
		/* The following are needed for different bit depths */
		if (originalImageDepth==16 || originalImageDepth==32) run(originalImageDepth + "-bit");
		run("Enhance Contrast...", "saturated=0 normalize");
		run("Invert");  /* Create an image that can be subtracted - this works better for color than Min */
		divider = (100 / abs(iShadowDarkness));
		run("Divide...", "value=[divider]");
	}
	function createShadowDropFromMask5(oShadowDrop, oShadowDisp, oShadowBlur, oShadowDarkness, oStroke) {
		/* Requires previous run of: originalImageDepth = bitDepth();
		because this version works with different bitDepths
		v161115 calls -5- variables: drop, displacement blur and darkness */
		showStatus("Creating drop shadow for labels . . . ");
		newImage("shadow", "8-bit black", imageWidth, imageHeight, 1);
		getSelectionFromMask("label_mask");
		getSelectionBounds(selMaskX, selMaskY, selMaskWidth, selMaskHeight);
		setSelectionLocation(selMaskX + oShadowDisp, selMaskY + oShadowDrop);
		setBackgroundColor(255,255,255);
		if (oStroke>0) run("Enlarge...", "enlarge=[oStroke] pixel"); /* Adjust shadow size so that shadow extends beyond stroke thickness */
		run("Clear");
		run("Select None");
		if (oShadowBlur>0) {
			run("Gaussian Blur...", "sigma=[oShadowBlur]");
			// run("Unsharp Mask...", "radius=[oShadowBlur] mask=0.4"); /* Make Gaussian shadow edge a little less fuzzy */
		}
		/* Now make sure shadow or glow does not impact outline */
		getSelectionFromMask("label_mask");
		if (oStroke>0) run("Enlarge...", "enlarge=[oStroke] pixel");
		setBackgroundColor(0,0,0);
		run("Clear");
		run("Select None");
		/* The following are needed for different bit depths */
		if (originalImageDepth==16 || originalImageDepth==32) run(originalImageDepth + "-bit");
		run("Enhance Contrast...", "saturated=0 normalize");
		divider = (100 / abs(oShadowDarkness));
		run("Divide...", "value=[divider]");
	}
	function expandLabel(string) {  /* Expands abbreviations typically used for compact column titles */
		string = replace(string, "Raw Int Den", "Raw Int. Density");
		string = replace(string, "FeretAngle", "Feret Angle");
		string = replace(string, "FiberThAnn", "Fiber Thckn. from Annulus");
		string = replace(string, "FiberLAnn", "Fiber Length from Annulus");
		string = replace(string, "FiberLR", "Fiber Length R");
		string = replace(string, "Da", "Diam:area");
		string = replace(string, "Dp", "Diam:perim.");
		string = replace(string, "equiv", "equiv.");
		string = replace(string, "_", " ");
		string = replace(string, "°", "degrees");
		string = replace(string, "0-90", "0-90°"); /* An exception to the above */
		string = replace(string, "°, degrees", "°"); /* That would be otherwise be too many degrees */
		string = replace(string, fromCharCode(0x00C2), ""); /* Remove mystery Â */
		string = replace(string, " ", fromCharCode(0x2009)); /* Use this last so all spaces converted */
		return string;
	}
	function fancyTextOverImage(shadowDrop,shadowDisp,shadowBlur,shadowDarkness,outlineStroke,innerShadowDrop,innerShadowDisp,innerShadowBlur,innerShadowDarkness) { /* Place text over image in a way that stands out; requires original "workingImage" and "textImage" and createShadowDropFromMask5 and createInnerShadowFromMask4 functions */
		selectWindow("textImage");
		run("Duplicate...", "title=label_mask");
		setThreshold(0, 128);
		setOption("BlackBackground", false);
		run("Convert to Mask");
		/*
		Create drop shadow if desired */
		if (shadowDrop!=0 || shadowDisp!=0)
			createShadowDropFromMask5(shadowDrop, shadowDisp, shadowBlur, shadowDarkness, outlineStroke);
		/*	Create inner shadow if desired */
		if (innerShadowDrop!=0 || innerShadowDisp!=0 || innerShadowBlur!=0) 
			createInnerShadowFromMask4(innerShadowDrop, innerShadowDisp, innerShadowBlur, innerShadowDarkness);
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
		run("Enlarge...", "enlarge=[outlineStroke] pixel");
		setBackgroundFromColorName(outlineColor);
		run("Clear");
		run("Enlarge...", "enlarge=[outlineStrokeOffset] pixel");
		run("Gaussian Blur...", "sigma=[outlineStrokeOffset]");
		run("Select None");
		/* Create text */
		getSelectionFromMask("label_mask");
		setBackgroundFromColorName(fontColor);
		run("Clear");
		run("Select None");
		/* Create inner shadow or glow if requested */
		if (isOpen("inner_shadow") && (innerShadowDarkness>0))
			imageCalculator("Subtract", workingImage,"inner_shadow");
		if (isOpen("inner_shadow") && (innerShadowDarkness<0))	/* Glow */
			imageCalculator("Add",workingImage,"inner_shadow");
		/* The following steps smooth the interior of the text labels */
		selectWindow("textImage");
		run("Restore Selection");
		if (selectionType()>=0) run("Make Inverse");
		else restoreExit("fancyTextOverImage function error: No selection to invert");
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
		else if (colorName == "pink") cA = newArray(255, 192, 203);
		else if (colorName == "green") cA = newArray(0,255,0); /* #00FF00 AKA Lime green */
		else if (colorName == "blue") cA = newArray(0,0,255);
		else if (colorName == "yellow") cA = newArray(255,255,0);
		else if (colorName == "orange") cA = newArray(255, 165, 0);
		else if (colorName == "garnet") cA = newArray(120,47,64);
		else if (colorName == "gold") cA = newArray(206,184,136);
		else if (colorName == "aqua_modern") cA = newArray(75,172,198); /* #4bacc6 AKA "Viking" aqua */
		else if (colorName == "blue_accent_modern") cA = newArray(79,129,189); /* #4f81bd */
		else if (colorName == "blue_dark_modern") cA = newArray(31,73,125);
		else if (colorName == "blue_modern") cA = newArray(58,93,174); /* #3a5dae */
		else if (colorName == "gray_modern") cA = newArray(83,86,90);
		else if (colorName == "green_dark_modern") cA = newArray(121,133,65);
		else if (colorName == "green_modern") cA = newArray(155,187,89); /* #9bbb59 AKA "Chelsea Cucumber" */
		else if (colorName == "green_modern_accent") cA = newArray(214,228,187); /* #D6E4BB AKA "Gin" */
		else if (colorName == "green_spring_accent") cA = newArray(0,255,102); /* #00FF66 AKA "Spring Green" */
		else if (colorName == "orange_modern") cA = newArray(247,150,70);
		else if (colorName == "pink_modern") cA = newArray(255,105,180);
		else if (colorName == "purple_modern") cA = newArray(128,100,162);
		else if (colorName == "jazzberry_jam") cA = newArray(165,11,94);
		else if (colorName == "red_N_modern") cA = newArray(227,24,55);
		else if (colorName == "red_modern") cA = newArray(192,80,77);
		else if (colorName == "tan_modern") cA = newArray(238,236,225);
		else if (colorName == "violet_modern") cA = newArray(76,65,132);
		else if (colorName == "yellow_modern") cA = newArray(247,238,69);
		/* Fluorescent Colors https://www.w3schools.com/colors/colors_crayola.asp */
		else if (colorName == "Radical Red") cA = newArray(255,53,94);			/* #FF355E */
		else if (colorName == "Wild Watermelon") cA = newArray(253,91,120);		/* #FD5B78 */
		else if (colorName == "Outrageous Orange") cA = newArray(255,96,55);	/* #FF6037 */
		else if (colorName == "Supernova Orange") cA = newArray(255,191,63);	/* FFBF3F Supernova Neon Orange*/
		else if (colorName == "Atomic Tangerine") cA = newArray(255,153,102);	/* #FF9966 */
		else if (colorName == "Neon Carrot") cA = newArray(255,153,51);			/* #FF9933 */
		else if (colorName == "Sunglow") cA = newArray(255,204,51); 			/* #FFCC33 */
		else if (colorName == "Laser Lemon") cA = newArray(255,255,102); 		/* #FFFF66 "Unmellow Yellow" */
		else if (colorName == "Electric Lime") cA = newArray(204,255,0); 		/* #CCFF00 */
		else if (colorName == "Screamin' Green") cA = newArray(102,255,102); 	/* #66FF66 */
		else if (colorName == "Magic Mint") cA = newArray(170,240,209); 		/* #AAF0D1 */
		else if (colorName == "Blizzard Blue") cA = newArray(80,191,230); 		/* #50BFE6 Malibu */
		else if (colorName == "Dodger Blue") cA = newArray(9,159,255);			/* #099FFF Dodger Neon Blue */
		else if (colorName == "Shocking Pink") cA = newArray(255,110,255);		/* #FF6EFF Ultra Pink */
		else if (colorName == "Razzle Dazzle Rose") cA = newArray(238,52,210); 	/* #EE34D2 */
		else if (colorName == "Hot Magenta") cA = newArray(255,0,204);			/* #FF00CC AKA Purple Pizzazz */
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
	/* Hex conversion below adapted from T.Ferreira, 20010.01 http://imagejdocu.tudor.lu/doku.php?id=macro:rgbtohex */
	function pad(n) {
		n = toString(n);
		if(lengthOf(n)==1) n = "0"+n;
		return n;
	}
	function getHexColorFromRGBArray(colorNameString) {
		colorArray = getColorArrayFromColorName(colorNameString);
		 r = toHex(colorArray[0]); g = toHex(colorArray[1]); b = toHex(colorArray[2]);
		 hexName= "#" + ""+pad(r) + ""+pad(g) + ""+pad(b);
		 return hexName;
	}
	function getLutsList() {
		/* v180723 added check for preferred LUTs */
		lutsCheck = 0;
		defaultLuts= getList("LUTs");
		Array.sort(defaultLuts);
		lutsDir = getDirectory("LUTs");
		/* A list of frequently used LUTs for the top of the menu list . . . */
		preferredLutsList = newArray("Your favorite LUTS here", "silver-asc", "viridis-linearlumin", "mpl-viridis", "mpl-plasma", "Glasbey", "Grays");
		preferredLuts = newArray(preferredLutsList.length);
		counter = 0;
		for (i=0; i<preferredLutsList.length; i++) {
			for (j=0; j<defaultLuts.length; j++) {
				if (preferredLutsList[i] == defaultLuts[j]) {
					preferredLuts[counter] = preferredLutsList[i];
					counter +=1;
					j = defaultLuts.length;
				}
			}
		}
		preferredLuts = Array.trim(preferredLuts, counter);
		lutsList=Array.concat(preferredLuts, defaultLuts);
		return lutsList; /* Required to return new array */
	}
	function loadLutColors(lut) {
		run(lut);
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
		*/
		systemFonts = getFontList();
		IJFonts = newArray("SansSerif", "Serif", "Monospaced");
		fontNameChoice = Array.concat(IJFonts,systemFonts);
		faveFontList = newArray("Your favorite fonts here", "Open Sans ExtraBold", "Fira Sans ExtraBold", "Fira Sans Ultra", "Fira Sans Condensed Ultra", "Arial Black", "Myriad Pro Black", "Montserrat Black", "Olympia-Extra Bold", "SansSerif", "Calibri", "Roboto", "Roboto Bk", "Tahoma", "Times New Roman", "Times", "Helvetica");
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
	function getSelectionFromMask(selection_Mask){
		batchMode = is("Batch Mode"); /* Store batch status mode before toggling */
		if (!batchMode) setBatchMode(true); /* Toggle batch mode on if previously off */
		tempTitle = getTitle();
		selectWindow(selection_Mask);
		run("Create Selection"); /* Selection inverted perhaps because the mask has an inverted LUT? */
		run("Make Inverse");
		selectWindow(tempTitle);
		run("Restore Selection");
		if (!batchMode) setBatchMode(false); /* Return to original batch mode setting */
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
	function removeTrailingZerosAndPeriod(string) { /* Removes any trailing zeros after a period */
		while (endsWith(string,".0")) {
			string=substring(string,0, lastIndexOf(string, ".0"));
		}
		while(endsWith(string,".")) {
			string=substring(string,0, lastIndexOf(string, "."));
		}
		return string;
	}
	function memFlush(waitTime) {
		run("Reset...", "reset=[Undo Buffer]"); 
		wait(waitTime);
		run("Reset...", "reset=[Locked Image]"); 
		wait(waitTime);
		call("java.lang.System.gc"); /* force a garbage collection */
		wait(waitTime);
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
		if (lastIndexOf(string, ".")!=-1) {
			knownExt = newArray("tif", "tiff", "TIF", "TIFF", "png", "PNG", "GIF", "gif", "jpg", "JPG", "jpeg", "JPEG", "jp2", "JP2", "txt", "TXT", "csv", "CSV");
			for (i=0; i<knownExt.length; i++) {
				index = lastIndexOf(string, "." + knownExt[i]);
				if (index>=(lengthOf(string)-(lengthOf(knownExt[i])+1))) string = substring(string, 0, index);
			}
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
	function unCleanLabel(string) {
	/* v161104 This function replaces special characters with standard characters for file system compatible filenames
	+ 041117 to remove spaces as well */
		string= replace(string, fromCharCode(178), "\\^2"); /* superscript 2 */
		string= replace(string, fromCharCode(179), "\\^3"); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, fromCharCode(0xFE63) + fromCharCode(185), "\\^-1"); /* Small hypen substituted for superscript minus as 0x207B does not display in table */
		string= replace(string, fromCharCode(0xFE63) + fromCharCode(178), "\\^-2"); /* Small hypen substituted for superscript minus as 0x207B does not display in table */
		string= replace(string, fromCharCode(181), "u"); /* micron units */
		string= replace(string, fromCharCode(197), "Angstrom"); /* Ångström unit symbol */
		string= replace(string, fromCharCode(0x2009) + fromCharCode(0x00B0), "deg"); /* replace thin spaces degrees combination */
		string= replace(string, fromCharCode(0x2009), "_"); /* Replace thin spaces  */
		string= replace(string, " ", "_"); /* Replace spaces - these can be a problem with image combination */
		string= replace(string, "_\\+", "\\+"); /* Clean up autofilenames */
		string= replace(string, "\\+\\+", "\\+"); /* Clean up autofilenames */
		string= replace(string, "__", "_"); /* Clean up autofilenames */
		return string;
	}
	function unitLabelFromString(string, imageUnit) {
	/* v180404 added Feret_MinDAngle_Offset */
		if (endsWith(string,"\)")) { /* Label with units from string if enclosed by parentheses */
			unitIndexStart = lastIndexOf(string, "\(");
			unitIndexEnd = lastIndexOf(string, "\)");
			stringUnit = substring(string, unitIndexStart+1, unitIndexEnd);
			unitCheck = matches(stringUnit, ".*[0-9].*");
			if (unitCheck==0) {  /* If the "unit" contains a number it probably isn't a unit */
				unitLabel = stringUnit;
			}
			else {
				unitLabel = "";
			}
		}
		else {
			if (string=="Area") unitLabel = imageUnit + fromCharCode(178);
			else if (string=="AR" || string=="Circ" || string=="Round" || string=="Solidity") unitLabel = "";
			else if (string=="Mean" || string=="StdDev" || string=="Mode" || string=="Min" || string=="Max" || string=="IntDen" || string=="Median" || string=="RawIntDen" || string=="Slice") unitLabel = "";
			else if (string=="Angle" || string=="FeretAngle" || string=="Angle_0-90" || string=="FeretAngle_0-90" || string=="Feret_MinDAngle_Offset" || string=="MinDistAngle") unitLabel = fromCharCode(0x00B0);
			else if (string=="%Area") unitLabel = "%";
			else unitLabel = imageUnit;
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
	*/