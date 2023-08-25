/*	Fork of ROI_Color_Coder.ijm  IJ BAR: https://github.com/tferr/Scripts#scripts
	https://imagej.net/doku.php?id=macro:roi_color_coder
	Colorizes ROIs by matching LUT indexes to measurements in the Results table. It is
	complementary to the ParticleAnalyzer (Analyze>Analyze Particles...), generating
	particle-size heat maps. Requires IJ 1.47r.
	Tiago Ferreira, v.5.4 2017.03.10 (add optional log10 scale) + pjl mods 3/13/2017.
	 + option to reverse LUT.
	 + dialog requester shows min and max values for all measurements to make it easier to choose a range 8/5/2016.
	 + optional min and max lines for ramp.
	 + optional mean and std. dev. lines for ramp.
	 + cleans up previous runs and checks for data.
	 + automated units + Legend title orientation choice 10/13-20/16.
	 + optional montage that combines the labeled image with the legend 10/1/2016.
	 + v170315 (updates to AR v.5.4 version i.e. includes log option).
	 + v170914 Added garbage clean up as suggested by Luc LaLonde at LBNL.
	 + v180104 Updated functions to latest versions.
	 + v180228 Fixed missing ramp labels.
	 + v180316 Fixed min-max label issue, reordered 1st menu
	+ v180831 Added check for Fiji_Plugins.
	+ v190329 Added expanded font choice (edit getFontChoiceList function to put favorites first in list). Updated functions.
	+ 070119 Expanded ROI check function with import options. Tweak ramp size.
	+ v190731 Fixed issue with coloring loop not advancing as expected for some conditions.
	+ v200706 Changed imageDepth variable name
	+ v210428-30 Updated ASC functions, disabled non-function experimental log option. Switched to expandable arrays, improved ramp labels
	+ v211025 updated functions  v211029 Added cividis.lut
	+ v211103 Expanded expandLabels function
	+ v211104: Updated stripKnownExtensionFromString function    v211112+v220616+v230505(f8)+060723(f10): Again  (f3)220510 updated checkForPlugins f4-5 updated pad function f6-7 updated color functions
	+ v230825:	Adds rangeFinder function. Intervals automatic.
*/
macro "ROI Color Coder with settings generated from data"{
	macroL = "BAR_ROI_Color_Coder+autoprefs_ASC_v230825.ijm";
	requires("1.53g"); /* Uses expandable arrays */
	if (!checkForPluginNameContains("Fiji_Plugins")) exit("Sorry this macro requires some functions in the Fiji_Plugins package");
	/* Needs Fiji_pluings for autoCrop */
	saveSettings;
   	close("*Ramp"); /* cleanup: closes previous ramp windows */
	// run("Remove Overlay");
	if (nImages==0){
		showMessageWithCancel("No images open or the ROI Manager is empty...\n"
        + "Run demo? (Results Table and ROI Manager will be cleared)");
	    runDemo();
	}
	run("Select None");
	/*	Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* Set the background to white */
	run("Colors...", "foreground=black background=white selection=yellow"); /* Set the preferred colors for these macros */
	setOption("BlackBackground", false);
	run("Appearance...", " "); if(is("Inverting LUT")) run("Invert LUT"); /* do not use Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background) https://imagej.net/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	id = getImageID();	t=getTitle(); /* get id of image and title */
	checkForUnits(); /* Required function */
	getPixelSize(unit, pixelWidth, pixelHeight);
	checkForRoiManager(); /* macro requires that the objects are in the ROI manager */
	checkForResults(); /* macro requires that there are results to display */
	nROIs = roiManager("count"); /* get number of ROIs to colorize */
	nRes = nResults;
	menuLimit = 0.8 * screenHeight; /* used to limit menu size for small screens */
	if (nRes!=nROIs) restoreExit("Exit: Results table \(" + nRes + "\) and ROI Manager \(" + nROIs + "\) mismatch."); /* exit so that this ambiguity can be cleared up */
	if (nROIs<=1) restoreExit("Exit: ROI Manager has only \(" + nROIs + "\) entries."); /* exit so that this ambiguity can be cleared up */
	items = nROIs;
	run("Remove Overlay");
	setBatchMode(true);
	sup2 = fromCharCode(178);
	degreeChar = fromCharCode(0x00B0);
	sigmaChar = fromCharCode(0x03C3);
	plusMinus = fromCharCode(0x00B1);
	tN = stripKnownExtensionFromString(t); /* as in N=name could also use File.nameWithoutExtension but that is specific to last opened file */
	tN = unCleanLabel(tN); /* remove special characters and spaces that might cause issues saving file */
	imageHeight = getHeight(); imageWidth = getWidth();
	rampH = round(0.89 * imageHeight); /* suggest ramp slightly small to allow room for labels */
	fontSize = maxOf(8,imageHeight/28); /* default fonts size based on imageHeight */
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
	/* create the dialog prompt */
	Dialog.create(macroL + ": " + tN);
	Dialog.addMessage("Macro version: " + macroL);
	Dialog.addChoice("Parameter", headingsWithRange, headingsWithRange[1]);
	luts=getLutsList(); /* I prefer this to new direct use of getList used in the recent versions of the BAR macro YMMV */
	Dialog.addChoice("LUT:", luts, luts[0]);
	Dialog.setInsets(0, 120, 12);
	Dialog.addCheckbox("Reverse LUT?", false); 
	Dialog.setInsets(-6, 0, -6);
	Dialog.addMessage("Color Coded Borders or Filled ROIs?");
	Dialog.addNumber("Outlines or ROIs?", 0, 0, 3, " Width in pixels \(0 to fill ROIs\)");
	Dialog.addSlider("Coding opacity (%):", 0, 100, 100);
	Dialog.setInsets(6, 0, 6);
	Dialog.addMessage("Legend \(ramp\):______________");
	unitChoice = newArray("Auto", "Manual", unit, unit+"^2", "None", "pixels", "pixels^2", fromCharCode(0x00B0), "degrees", "radians", "%", "arb.");
	Dialog.addChoice("Unit \("+unit+"\) Label:", unitChoice, unitChoice[0]);
	Dialog.setInsets(-42, 197, -5);
	Dialog.addMessage("Auto based on\nselected parameter");
	Dialog.addString("Range:", "AutoMin-AutoMax", 11);
	Dialog.setInsets(-35, 235, 0);
	Dialog.addMessage("(e.g., 10-100)");
	Dialog.setInsets(-8, 120, 4);
	Dialog.addCheckbox("Add labels at true Min. & Max. if inside range", true);
	Dialog.addString("No. of intervals:", "Auto",11);
	Dialog.addChoice("Decimal places:", newArray("Auto", "Manual", "Scientific", "0", "1", "2", "3", "4"), "Auto");
	Dialog.addChoice("LUT height \(pxls\):", newArray(rampH, 128, 256, 512, 1024, 2048, 4096), rampH);
	Dialog.setInsets(-38, 195, 0);
	Dialog.addMessage(rampH + " pxls suggested\nby image height");
	fontStyleChoice = newArray("bold", "bold antialiased", "italic", "italic antialiased", "bold italic", "bold italic antialiased", "unstyled");
	Dialog.addChoice("Font style:", fontStyleChoice, fontStyleChoice[1]);
	fontNameChoice = getFontChoiceList();
	Dialog.addChoice("Font name:", fontNameChoice, fontNameChoice[0]);
	Dialog.addNumber("Font_size \(height\):", fontSize, 0, 3, "pxls");
	Dialog.setInsets(-25, 205, 0);
	Dialog.addCheckbox("Draw tick marks", true);
	Dialog.setInsets(2, 120, 0);
	Dialog.addCheckbox("Force legend label to right of and || to ramp", true);
	Dialog.setInsets(-6, 0, -2);
	Dialog.addMessage("Ramp Stats Labels:______________");
	Dialog.setInsets(0, 120, 0);
	Dialog.addCheckbox("Stats: Add labels at mean and " + plusMinus + " " + sigmaChar, true);
	Dialog.addNumber("Tick length:", 50, 0, 3, "% of major tick. Also Min. & Max. Lines");
	Dialog.addNumber("Stats label font:", 100, 0, 3, "% of font size. Also Min. & Max. Lines");
	Dialog.addHelp("https://imagej.net/doku.php?id=macro:roi_color_coder");
	Dialog.show;
		parameterWithLabel= Dialog.getChoice;
		parameter= substring(parameterWithLabel, 0, indexOf(parameterWithLabel, ":  "));
		lut= Dialog.getChoice;
		revLut= Dialog.getCheckbox;
		stroke= Dialog.getNumber;
		alpha= pad(toHex(255*Dialog.getNumber/100));
		unitLabel= Dialog.getChoice();
		rangeS= Dialog.getString; /* changed from original to allow negative values - see below */
		rampMinMaxLines= Dialog.getCheckbox;
		numIntervals= Dialog.getString; /* The number intervals along ramp */
		dpChoice= Dialog.getChoice;
		rampHChoice= parseFloat(Dialog.getChoice);
		fontStyle= Dialog.getChoice;
			if (fontStyle=="unstyled") fontStyle="";
		fontName= Dialog.getChoice;
		fontSize= Dialog.getNumber;
		ticks= Dialog.getCheckbox;
		rotLegend= Dialog.getCheckbox;
		statsRampLines= Dialog.getCheckbox;
		statsRampTicks= Dialog.getNumber;
		thinLinesFontSTweak= Dialog.getNumber;
//
	rampW = round(rampH/8); /* this will be updated later */ 
	rampUnitLabel = replace(unitLabel, fromCharCode(0x00B0), "degrees"); /* replace lonely Â° symbol */
	if ((rotLegend && (rampHChoice==rampH)) || (rampW < getStringWidth(rampUnitLabel))) rampH = imageHeight - fontSize; /* tweaks automatic height selection for vertical legend */
	else rampH = rampHChoice;
	rampW = round(rampH/8); 
	range = split(rangeS, "-");
	if (lengthOf(range)==1) {
		rampMin= NaN;
		rampMax= parseFloat(range[0]);
	} else {
		rampMin= parseFloat(range[0]);
		rampMax= parseFloat(range[1]);
	}
	if (indexOf(rangeS, "-")==0) rampMin = 0 - rampMin; /* checks to see if rampMin is a negative value (lets hope the rampMax isn't). */
	fontSR2 = fontSize * thinLinesFontSTweak/100;
	rampLW = maxOf(1, round(rampH/512)); /* ramp line width with a minimum of 1 pixel */
	minmaxLW = round(rampLW / 4); /* line widths for ramp stats */
	/* get values for chosen parameter */
	values= newArray;
	if (parameter!="Object"){
		for (i=0; i<items; i++)
			values[i] = getResult(parameter,i);
	}
	else for (i=0; i<items; i++) values[i] = i+1;
	Array.getStatistics(values, arrayMin, arrayMax, arrayMean, arraySD); 
	coeffVar = arraySD*100/arrayMean;
	arrayRange = arrayMax-arrayMin;
	if (isNaN(rampMin)){
		rampMin= arrayMin; /* i.e. auto */
		rampMin = rangeFinder(rampMin,false);
	} 
	if (isNaN(rampMax)){
		rampMax= arrayMax; /* i.e. auto */
		rampMax = rangeFinder(rampMax,true);
	}
	rampRange = rampMax - rampMin;
	if (isNaN(numIntervals)){
		intStr = d2s(rampRange,-1);
		intStr = substring(intStr,0,indexOf(intStr,"E"));
		numIntervals =  parseFloat(intStr);
		if (numIntervals>4) numIntervals = Math.ceil(numIntervals);
		else if (numIntervals<2) numIntervals = Math.ceil(10 * numIntervals);
		else numIntervals = Math.ceil(5 * numIntervals);
	}
	else numIntervals = parseInt(numIntervals);
	rampRange = rampMax - rampMin;
	numLabels= numIntervals + 1;
	sortedValues = Array.copy(values);
	sortedValues = Array.sort(sortedValues); /* all this effort to get the median without sorting the original array! */
	arrayMedian = sortedValues[round(items/2)];  /* you could extend this obviously to provide quartiles but at that point you might as well use Excel */
/* Create the parameter label */
	if (unitLabel=="Auto") unitLabel = unitLabelFromString(parameter, unit);
	if (unitLabel=="Manual") {
		unitLabel = unitLabelFromString(parameter, unit);
			Dialog.create("Manual unit input");
			Dialog.addString("Label:", unitLabel, 8);
			Dialog.addMessage("^2 & um etc. replaced by " + fromCharCode(178) + " & " + fromCharCode(181) + "m...");
			Dialog.show();
			unitLabel = Dialog.getString();
	}
	if (unitLabel=="None") unitLabel = ""; 
	if (unitLabel=="") unitLabelExists = false;
	else unitLabelExists = true;
	parameterLabel = stripUnitFromString(parameter);
	unitLabel= cleanLabel(unitLabel);
/*
		Create LUT-map legend
*/
	rampW = round(rampH/8); canvasH = round(4 * fontSize + rampH); canvasW = round(rampH/2); tickL = round(rampW/4);
	if (statsRampLines || rampMinMaxLines) tickL = round(tickL/2); /* reduce tick length to provide more space for inside label */
	tickLR = round(tickL * statsRampTicks/100);
	getLocationAndSize(imgx, imgy, imgwidth, imgheight);
	call("ij.gui.ImageWindow.setNextLocation", imgx + imgwidth, imgy);
	newImage(tN + "_" + parameterLabel +"_Ramp", "8-bit ramp", rampH, rampW, 1);
	/* ramp color/gray range is horizontal only so must be rotated later */
	if (revLut) run("Flip Horizontally");
	tR = getTitle; /* short variable label for ramp */
	roiColors= loadLutColors(lut); /* load the LUT as a hexColor array: requires function */
	/* continue the legend design */
	setColor(0, 0, 0);
	setBackgroundColor(255, 255, 255);
	setFont(fontName, fontSize, fontStyle);
	if (imageDepth!=8 || lut!="Grays") run("RGB Color"); /* converts ramp to RGB if not using grays only */
	setLineWidth(rampLW*2);
	if (ticks) {
		drawRect(0, 0, rampH, rampW);
		/* The next steps add the top and bottom ticks */
		rampWT = rampW + 2*rampLW;
		run("Canvas Size...", "width="+ rampH +" height="+ rampWT +" position=Top-Center");
		drawLine(0, rampW-1, 0,  rampW-1 + 2*rampLW); /* left/bottom tick - remember coordinate range is one less then max dimension because coordinates start at zero */
		drawLine(rampH-1, rampW-1, rampH-1, rampW + 2*rampLW - 1); /* right/top tick */
	}
	run("Rotate 90 Degrees Left");
	run("Canvas Size...", "width="+ canvasW +" height="+ canvasH +" position=Center-Left");
	if (dpChoice=="Auto")
		decPlaces = autoCalculateDecPlaces3(rampMin,rampMax,numIntervals);
	else if (dpChoice=="Manual") 
		decPlaces=getNumber("Choose Number of Decimal Places", 0);
	else if (dpChoice=="Scientific")
		decPlaces = -1;
	else decPlaces = parseFloat(dpChoice);
	if (parameter=="Object") decPlaces = 0; /* This should be an integer */
	/* draw ticks and values */
	rampOffset = (getHeight-rampH)/2; /* getHeight-rampH ~ 2 * fontSize */
	step = rampH;
	if (numLabels>2) step /= numIntervals;
    setLineWidth(rampLW);
	/* now to see if the selected range values are within 98% of actual */
	if (0.98*rampMin>arrayMin || rampMax<0.98*arrayMax) rampMinMaxOOR = true;
	else rampMinMaxOOR = false;
	if ((rampMin<(0.98*arrayMin) || (0.98*rampMax)>arrayMax) && rampMinMaxLines)
		rampMinMaxLines = true;
	else rampMinMaxLines = false;
	stepV = rampRange/numIntervals;
	/* Create array of ramp labels that can be used to optimize label length */
	rampLabelString = newArray;
	for (i=0,maxDP=0; i<numLabels; i++) {
		rampLabel = rampMin + i * stepV;
		rampLabelString[i] = d2s(rampLabel,decPlaces);
	}
	if (dpChoice=="Auto"){
		/* Remove excess zeros from ramp labels but not if manually set */
		for (i=0; i<decPlaces; i++) {
			dN = newArray;
			for (j=0,countL=0; j<numLabels; j++){
				iP = indexOf(rampLabelString[j], ".");
				if (endsWith(rampLabelString[i],"0") && iP>0) countL++;
			}
			if (countL==numLabels){
				for (j=0; j<numLabels; j++){
					if (endsWith(rampLabelString[j],"0")){
						rampLabelString[j] = substring(rampLabelString[j],0,lengthOf(rampLabelString[j])-1);
						if (endsWith(rampLabelString[j],".")) rampLabelString[j] = substring(rampLabelString[j],0,lengthOf(rampLabelString[j])-1);
					}
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
	for (i=0; i<numLabels; i++) {
		yPos = rampH + rampOffset - round(i*step) - 1; /* minus 1 corrects for coordinates starting at zero */
		rampLabel = rampMin + i * stepV;
		/*Now add overrun text labels at the top and/or bottom of the ramp if the true data extends beyond the ramp range */
		if (i==0 && rampMin>(1.001*arrayMin))
			rampLabelString[i] = fromCharCode(0x2264) + rampLabelString[i];
		if (i==(numLabels-1) && rampMax<(0.999*arrayMax))
			rampLabelString[i] = fromCharCode(0x2265) + rampLabelString[i];
		drawString(rampLabelString[i], rampW+4*rampLW, round(yPos+fontSize/2));
		if (ticks) {
			if (i==0 || i==numIntervals) {
				setLineWidth(rampLW/2);
				drawLine(rampW, yPos, rampW+rampLW, yPos); /* right tick extends over border slightly as subtle cross-tick */
			}	
			else {
				setLineWidth(rampLW);
				drawLine(0, yPos, tickL, yPos);					/* left tick */
				drawLine(rampW-1-tickL, yPos, rampW, yPos);
				setLineWidth(rampLW/2);
				drawLine(rampW, yPos, rampW+rampLW, yPos); /* right tick extends over border slightly as subtle cross-tick */
				setLineWidth(rampLW); /* Rest line width */
			}
		}
	}
	/* now add lines and the true min and max and for stats if chosen in previous dialog */
	if (rampMinMaxLines || statsRampLines) {
		newImage("label_mask", "8-bit black", getWidth(), getHeight(), 1);
		setColor("white");
		setLineWidth(rampLW);
		if (rampMinMaxLines) {
			if (rampMin==rampMax) restoreExit("Something terribly wrong with this range!");
			trueMaxFactor = (arrayMax-rampMin)/(rampRange);
			rampMaxPos = round(fontSize/2 + (rampH * (1 - trueMaxFactor)) +1.5*fontSize)-1;
			trueMinFactor = (arrayMin-rampMin)/(rampRange);
			rampMinPos = round(fontSize/2 + (rampH * (1 - trueMinFactor)) +1.5*fontSize)-1;
			if (trueMaxFactor<1) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("Max", round((rampW-getStringWidth("Max"))/2), round(rampMaxPos+0.5*fontSR2));
				drawLine(rampLW, rampMaxPos, tickLR, rampMaxPos);
				drawLine(rampW-1-tickLR, rampMaxPos, rampW-rampLW-1, rampMaxPos);
			}
			if (trueMinFactor>0) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("Min", round((rampW-getStringWidth("Min"))/2), round(rampMinPos+0.5*fontSR2));
				drawLine(rampLW, rampMinPos, tickLR, rampMinPos);
				drawLine(rampW-1-tickLR, rampMinPos, rampW-rampLW-1, rampMinPos);
			}
		}
		if (statsRampLines) {
			meanFactor = (arrayMean-rampMin)/(rampRange);
			plusSDFactor =  (arrayMean+arraySD-rampMin)/(rampRange);
			minusSDFactor =  (arrayMean-arraySD-rampMin)/(rampRange);
			meanPos = round(fontSize/2 + (rampH * (1 - meanFactor)) +1.5*fontSize)-1;
			plusSDPos = round(fontSize/2 + (rampH * (1 - plusSDFactor)) +1.5*fontSize)-1;
			minusSDPos = round(fontSize/2 + (rampH * (1 - minusSDFactor)) +1.5*fontSize)-1;
			setFont(fontName, 0.9*fontSR2, fontStyle);
			drawString("Mean", round((rampW-getStringWidth("Mean"))/2), round(meanPos+0.4*fontSR2));
			drawLine(rampLW, meanPos, tickLR, meanPos);
			drawLine(rampW-1-tickLR, meanPos, rampW-rampLW-1, meanPos);
			if (plusSDFactor<1) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("+"+sigmaChar, round((rampW-getStringWidth("+"+sigmaChar))/2), round(plusSDPos+0.5*fontSR2));
				drawLine(rampLW, plusSDPos, tickLR, plusSDPos);
				drawLine(rampW-1-tickLR, plusSDPos, rampW-rampLW-1, plusSDPos);
			}
			if (minusSDFactor>0) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("-"+sigmaChar, round((rampW-getStringWidth("-"+sigmaChar))/2), round(minusSDPos+0.5*fontSR2));
				drawLine(rampLW, minusSDPos, tickLR, minusSDPos);
				drawLine(rampW-1-tickLR, minusSDPos, rampW-rampLW-1, minusSDPos);
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
		run("Enlarge...", "enlarge=[rampOutlineStroke] pixel");
		setBackgroundColor(0, 0, 0);
		run("Clear");
		run("Enlarge...", "enlarge=[rampOutlineStroke] pixel");
		run("Gaussian Blur...", "sigma=[rampOutlineStroke]");	
		run("Select None");
		getSelectionFromMask("label_mask");
		setBackgroundColor(255, 255, 255);
		run("Clear");
		run("Select None");
		/* The following steps smooth the interior of the text labels */
		selectWindow("stats_text");
		getSelectionFromMask("label_mask");
		run("Make Inverse");
		run("Invert");
		run("Select None");
		imageCalculator("Min",tR,"stats_text");
		closeImageByTitle("label_mask");
		closeImageByTitle("stats_text");
		/* reset colors and font */
		setFont(fontName, fontSize, fontStyle);
		setColor(0,0,0);
	}
	/*	parse symbols in unit and draw final label below ramp */
	selectWindow(tR);
	rampParameterLabel= cleanLabel(parameterLabel);
	rampUnitLabel = replace(unitLabel, fromCharCode(0x00B0), "degrees"); /* replace lonely ° symbol */
	if (rampW>getStringWidth(rampUnitLabel) && rampW>getStringWidth(rampParameterLabel) && !rotLegend) { /* can center align if labels shorter than ramp width */
		if (rampParameterLabel!="") drawString(rampParameterLabel, round((rampW-(getStringWidth(rampParameterLabel)))/2), round(1.5*fontSize));
		if (rampUnitLabel!="") drawString(rampUnitLabel, round((rampW-(getStringWidth(rampUnitLabel)))/2), round(canvasH-0.5*fontSize));
	}
	else { /* need to left align if labels are longer and increase distance from ramp */
		run("Auto Crop (guess background color)");
		getDisplayedArea(null, null, canvasW, canvasH);
		run("Rotate 90 Degrees Left");
		canvasW = getHeight + round(2.5*fontSize);
		if (unitLabelExists) rampParameterLabel += ", " + rampUnitLabel;
		else rampParameterLabel += " " + rampUnitLabel;
		rampParameterLabel = expandLabel(rampParameterLabel);
		rampParameterLabel = replace(rampParameterLabel, fromCharCode(0x2009), " "); /* expand again now we have the space */
		rampParameterLabel = replace(rampParameterLabel, "px", "pixels"); /* expand "px" used to keep Results columns narrower */
		run("Canvas Size...", "width="+ canvasH +" height="+ canvasW+" position=Bottom-Center");
		if (rampParameterLabel!="") drawString(rampParameterLabel, round((canvasH-(getStringWidth(rampParameterLabel)))/2), round(1.5*fontSize));
		run("Rotate 90 Degrees Right");
	}
	run("Auto Crop (guess background color)");
	setBatchMode("true");
	getDisplayedArea(null, null, canvasW, canvasH);
	canvasW += round(imageWidth/150); canvasH += round(imageHeight/150); /* add padding to legend box */
	run("Canvas Size...", "width="+ canvasW +" height="+ canvasH +" position=Center");
	/*
		iterate through the ROI Manager list and colorize ROIs
	*/
	selectImage(id);
	legendMin = rampMin;
	legendMax = rampMax;
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
	}
	/*	display result */
	roiManager("Show all");
	if (countNaN!=0)
		print("\n>>>> ROI Color Coder:\n"
			+ "Some values from the \""+ parameter +"\" column could not be retrieved.\n"
			+ countNaN +" ROI(s) were labeled with a default color.");
	roiManager("Show All without labels");
	run("Flatten");
	tNC = tN + "_" + parameter + "-coded";
	rename(tNC);
	Dialog.create("Combine labeled image and color-code legend?");
		comboChoice = newArray("No","Image + color-code legend", "Auto-cropped image + color-code legend","Manually cropped image + color-code legend");
		Dialog.addRadioButtonGroup("Combine labeled image with color-code legend?", comboChoice, 5, 1,  comboChoice[1]) ;
	Dialog.show();
		createCombo = Dialog.getRadioButton;
	if (createCombo!="No") {
		if (indexOf(createCombo,"cropped")>0){
			if (is("Batch Mode")==true) setBatchMode("exit & display");	/* toggle batch mode off */
			selectWindow(tNC);
			run("Duplicate...", "title=" + tNC + "_crop");
			cropID = getImageID;
			run("Select Bounding Box (guess background color)");
			run("Enlarge...", "enlarge=" + round(imageHeight*0.02) + " pixel"); /* Adds a 2% margin */
			if (startsWith(createCombo,"Manual")) {
				getSelectionBounds(xA, yA, widthA, heightA);
				makeRectangle(maxOf(2,xA), maxOf(2,yA), minOf(imageWidth-4,widthA), minOf(imageHeight-4,heightA));
				setTool("rectangle");
				title = "Crop Location for Combined Image";
				msg = "1. Select the area that you want to crop to. 2. Click on OK";
				waitForUser(title, msg);
			}
			if (is("Batch Mode")==false) setBatchMode(true);	/* toggle batch mode back on */
			selectImage(cropID);
			if(selectionType>=0) run("Crop");
			else IJ.log("Combination with cropped image desired by no crop made");
			run("Select None");
			closeImageByTitle(tNC);
			rename(tNC);
			imageHeight = getHeight();
			imageWidth = getWidth();
		}
		if (canvasH>imageHeight){
			rampScale = imageHeight/canvasH;
			selectWindow(tR);
			run("Scale...", "x="+rampScale+" y="+rampScale+" interpolation=Bicubic average create title=scaled_ramp");
			closeImageByTitle(tR);
			rename(tR);
			canvasH = getHeight(); /* update ramp height */
			canvasW = getWidth(); /* update ramp height */
		}
		rampMargin = maxOf(2,imageWidth/500);
		rampSelW = canvasW + rampMargin;
		comboW = imageWidth + rampSelW;
		if (is("Batch Mode")==true) setBatchMode("exit & display");	/* toggle batch mode off */
		selectWindow(tNC);
		run("Canvas Size...", "width="+comboW+" height="+imageHeight+" position=Top-Left");
		selectWindow(tR);
		wait(5);
		Image.copy;
		selectWindow(tNC);
		wait(5);
		Image.paste(imageWidth + maxOf(2,imageWidth/500),round((imageHeight-canvasH)/2));
		rename(tNC + "+ramp");
		if (imageDepth==8 && lut=="Grays" && is("grayscale")) run("8-bit"); /* restores gray if all gray settings */
		closeImageByTitle(tR);
	}
	setBatchMode("exit & display");
	restoreSettings;
	call("java.lang.System.gc"); 
	showStatus(macroL + " macro finished");
	beep(); wait(300); beep(); wait(300); beep();
}
/*
			( 8(|)	( 8(|)	Functions	@@@@@:-)	@@@@@:-)
*/
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
			v190628 adds option to import saved ROI set
			v210428	include thresholding if necessary and color check
			NOTE: Requires ASC restoreExit function, which assumes that saveSettings has been run at the beginning of the macro
			*/
		functionL = "checkForRoiManager_v210428";
		nROIs = roiManager("count");
		nRes = nResults; /* Used to check for ROIs:Results mismatch */
		if(nROIs==0 || nROIs!=nRes){
			Dialog.create("ROI options: " + functionL);
				Dialog.addMessage("This macro requires that all objects have been loaded into the ROI manager.\n \nThere are   " + nRes +"   results.\nThere are   " + nROIs +"   ROIs.\nDo you want to:");
				if(nROIs==0) Dialog.addCheckbox("Import a saved ROI list",false);
				else Dialog.addCheckbox("Replace the current ROI list with a saved ROI list",false);
				if(nRes==0) Dialog.addCheckbox("Import a Results Table \(csv\) file",false);
				else Dialog.addCheckbox("Clear Results Table and import saved csv",false);
				Dialog.addCheckbox("Clear ROI list and Results Table and reanalyze \(overrides above selections\)",true);
				if (!is("binary")) Dialog.addMessage("The active image is not binary, so it may require thresholding before analysis");
				Dialog.addCheckbox("Get me out of here, I am having second thoughts . . .",false);
			Dialog.show();
				importROI = Dialog.getCheckbox;
				importResults = Dialog.getCheckbox;
				runAnalyze = Dialog.getCheckbox;
				if (Dialog.getCheckbox) restoreExit("Sorry this did not work out for you.");
			if (runAnalyze) {
				if (!is("binary")){
					if (is("grayscale") && bitDepth()>8){
						proceed = getBoolean("Image is grayscale but not 8-bit, convert it to 8-bit?", "Convert for thresholding", "Get me out of here");
						if (proceed) run("8-bit");
						else restoreExit("Goodbye, perhaps analyze first?");
					}
					if (bitDepth()==24){
						colorThreshold = getBoolean("Active image is RGB, so analysis requires thresholding", "Color Threshold", "Convert to 8-bit and threshold");
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
						if (is("Inverting LUT"))  {
							trueLUT = getBoolean("The LUT appears to be inverted, do you want the true LUT?", "Yes Please", "No Thanks");
							if (trueLUT) run("Invert LUT");
						}
					}
				}
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
		string= replace(string, "\\^-"+fromCharCode(185), "-" + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-"+fromCharCode(178), "-" + fromCharCode(178)); /* superscript -2 */
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
			str = str.replace(fromCharCode(0x2009)," ");
		}
		while (indexOf(str,"_")>=0) str = str.replace("_", " ");
		while (indexOf(str,"  ")>=0) str = str.replace("  ", " ");
		while (endsWith(str," ")) str = str.substring(0,lengthOf(str)-1);
		return str;
	}
  	function getFontChoiceList() {
		/*	v180723 first version
			v180828 Changed order of favorites
			v190108 Longer list of favorites
			v210429 Expandable array version
		*/
		systemFonts = getFontList();
		IJFonts = newArray("SansSerif", "Serif", "Monospaced");
		fontNameChoice = Array.concat(IJFonts,systemFonts);
		faveFontList = newArray("Your favorite fonts here", "Open Sans ExtraBold", "Fira Sans ExtraBold", "Noto Sans Black", "Arial Black", "Montserrat Black", "Lato Black", "Roboto Black", "Merriweather Black", "Alegreya Black", "Tahoma Bold", "Calibri Bold", "Helvetica", "SansSerif", "Calibri", "Roboto", "Tahoma", "Times New Roman Bold", "Times Bold", "Serif");
		faveFontListCheck = newArray(faveFontList.length);
		for (i=0, countF=0; i<faveFontList.length; i++) {
			for (j=0; j<fontNameChoice.length; j++) {
				if (faveFontList[i] == fontNameChoice[j]) {
					faveFontListCheck[countF] = faveFontList[i];
					countF++;
					j = fontNameChoice.length;
				}
			}
		}
		fontNameChoice = Array.concat(faveFontListCheck,fontNameChoice);
		return fontNameChoice;
	}
	function getLutsList() {
		/* v180723 added check for preferred LUTs
			v210429 expandable array version   v211029 added cividis.lut */
		defaultLuts= getList("LUTs");
		Array.sort(defaultLuts);
		lutsDir = getDirectory("LUTs");
		/* A list of frequently used LUTs for the top of the menu list . . . */
		preferredLutsList = newArray("Your favorite LUTS here", "cividis", "viridis-linearlumin", "silver-asc", "mpl-viridis", "mpl-plasma", "Glasbey", "Grays");
		preferredLuts = newArray;
		for (i=0, countL=0; i<preferredLutsList.length; i++) {
			for (j=0; j<defaultLuts.length; j++) {
				if (preferredLutsList[i] == defaultLuts[j]) {
					preferredLuts[countL] = preferredLutsList[i];
					countL++;
					j = defaultLuts.length;
				}
			}
		}
		preferredLuts = Array.trim(preferredLuts, countL);
		lutsList=Array.concat(preferredLuts, defaultLuts);
		return lutsList; /* Required to return new array */
	}
	function indexOfArray(array,string, default) {
		/* v190423 Adds "default" parameter (use -1 for backwards compatibility). Returns only first instance of string */
		index = default;
		for (i=0; i<lengthOf(array); i++){
			if (array[i]==string) {
				index = i;
				i = lengthOf(array);
			}
		}
		return index;
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
	function pad(n) {
	  /* This version by Tiago Ferreira 6/6/2022 eliminates the toString macro function */
	  if (lengthOf(n)==1) n= "0"+n; return n;
	  if (lengthOf(""+n)==1) n= "0"+n; return n;
	}
	/*
	End of Color Functions 
	*/
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
		function rangeFinder(dataExtreme,max){
	/*	For finding good end values for ramps and plot ranges.
		v230824: 1st version  Peter J. Lee Applied Superconductivity Center FSU */
		rangeExtremeStr = d2s(dataExtreme,-2);
		if (max) rangeExtremeA = Math.ceil(10 * parseFloat(substring(rangeExtremeStr,0,indexOf(rangeExtremeStr,"E")))) / 10;
		else rangeExtremeA = Math.floor(10 * parseFloat(substring(rangeExtremeStr,0,indexOf(rangeExtremeStr,"E")))) / 10;
		rangeExtremeStrB = substring(rangeExtremeStr,indexOf(rangeExtremeStr,"E")+1);
		rangeExtreme = parseFloat(rangeExtremeA + "E" + rangeExtremeStrB);
		return rangeExtreme;
	}
	function restoreExit(message){ /* Make a clean exit from a macro, restoring previous settings */
		/* 9/9/2017 added Garbage clean up suggested by Luc LaLonde - LBNL */
		restoreSettings(); /* Restore previous settings before exiting */
		setBatchMode("exit & display"); /* Probably not necessary if exiting gracefully but otherwise harmless */
		run("Collect Garbage");
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
		v230607: Quick fix for infinite loop on one of while statements.
		v230614: Added AVI.
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
			knownExt = newArray("avi", "AVI", "dsx", "DSX", "tif", "tiff", "TIF", "TIFF", "png", "PNG", "GIF", "gif", "jpg", "JPG", "jpeg", "JPEG", "jp2", "JP2", "txt", "TXT", "csv", "CSV","xlsx","XLSX");
			kEL = knownExt.length;
			chanLabels = newArray("\(red\)","\(green\)","\(blue\)");
			for (i=0,k=0; i<kEL; i++) {
				kExtn = "." + knownExt[i];
				for (j=0; j<3; j++){ /* Looking for channel-label-trapped extensions */
					iChanLabels = lastIndexOf(string, chanLabels[j])-1;
					if (iChanLabels>0){
						preChan = substring(string,0,iChanLabels);
						postChan = substring(string,iChanLabels);
						while (indexOf(preChan,kExtn)>=0 && k<10){  /* k counter quick fix for infinite loop */
							string = replace(preChan,kExtn,"") + postChan;
							k++;
						}
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
	function unCleanLabel(string) {
	/* v161104 This function replaces special characters with standard characters for file system compatible filenames.
	+ 041117b to remove spaces as well.
	+ v220126 added getInfo("micrometer.abbreviation").
	+ v220128 add loops that allow removal of multiple duplication.
	+ v220131 fixed so that suffix cleanup works even if extensions are included.
	+ v220616 Minor index range fix that does not seem to have an impact if macro is working as planned. v220715 added 8-bit to unwanted dupes. v220812 minor changes to micron and Ångström handling
	*/
		/* Remove bad characters */
		string= replace(string, fromCharCode(178), "\\^2"); /* superscript 2 */
		string= replace(string, fromCharCode(179), "\\^3"); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, fromCharCode(0xFE63) + fromCharCode(185), "\\^-1"); /* Small hyphen substituted for superscript minus as 0x207B does not display in table */
		string= replace(string, fromCharCode(0xFE63) + fromCharCode(178), "\\^-2"); /* Small hyphen substituted for superscript minus as 0x207B does not display in table */
		string= replace(string, fromCharCode(181)+"m", "um"); /* micron units */
		string= replace(string, getInfo("micrometer.abbreviation"), "um"); /* micron units */
		string= replace(string, fromCharCode(197), "Angstrom"); /* Ångström unit symbol */
		string= replace(string, fromCharCode(0x212B), "Angstrom"); /* the other Ångström unit symbol */
		string= replace(string, fromCharCode(0x2009) + fromCharCode(0x00B0), "deg"); /* replace thin spaces degrees combination */
		string= replace(string, fromCharCode(0x2009), "_"); /* Replace thin spaces  */
		string= replace(string, "%", "pc"); /* % causes issues with html listing */
		string= replace(string, " ", "_"); /* Replace spaces - these can be a problem with image combination */
		/* Remove duplicate strings */
		unwantedDupes = newArray("8bit","8-bit","lzw");
		for (i=0; i<lengthOf(unwantedDupes); i++){
			iLast = lastIndexOf(string,unwantedDupes[i]);
			iFirst = indexOf(string,unwantedDupes[i]);
			if (iFirst!=iLast) {
				string = substring(string,0,iFirst) + substring(string,iFirst + lengthOf(unwantedDupes[i]));
				i=-1; /* check again */
			}
		}
		unwantedDbls = newArray("_-","-_","__","--","\\+\\+");
		for (i=0; i<lengthOf(unwantedDbls); i++){
			iFirst = indexOf(string,unwantedDbls[i]);
			if (iFirst>=0) {
				string = substring(string,0,iFirst) + substring(string,iFirst + lengthOf(unwantedDbls[i])/2);
				i=-1; /* check again */
			}
		}
		string= replace(string, "_\\+", "\\+"); /* Clean up autofilenames */
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
		v210823 REQUIRES ASC function indexOfArray(array,string,default) for expanded "unitless" array
		*/
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
			unitLess = newArray("Circ.","Slice","AR","Round","Solidity","Image_Name","PixelAR","ROI_name","ObjectN","AR_Box","AR_Feret","Rnd_Feret","Compact_Feret","Elongation","Thinnes_Ratio","Squarity_AP","Squarity_AF","Squarity_Ff","Convexity","Rndnss_cAR","Fbr_Snk_Crl","Fbr_Rss2_Crl","AR_Fbr_Snk","Extent","HSF","HSFR","Hexagonality");
			angleUnits = newArray("Angle","FeretAngle","Cir_to_El_Tilt","Angle_0-90°","Angle_0-90","FeretAngle0to90","Feret_MinDAngle_Offset","MinDistAngle");
			chooseUnits = newArray("Mean" ,"StdDev" ,"Mode" ,"Min" ,"Max" ,"IntDen" ,"Median" ,"RawIntDen" ,"Slice");
			if (string=="Area") unitLabel = imageUnit + fromCharCode(178);
			else if (indexOfArray(unitLess,string,-1)>=0) unitLabel = "None";
			else if (indexOfArray(chooseUnits,string,-1)>=0) unitLabel = "";
			else if (indexOfArray(angleUnits,string,-1)>=0) unitLabel = fromCharCode(0x00B0);
			else if (string=="%Area") unitLabel = "%";
			else unitLabel = imageUnit;
		}
		return unitLabel;
	}