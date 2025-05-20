/* This macro is based on the Line-Color_Coder macros which itself was based on ROI_Color_Coder.ijm
	IJ BAR: https://github.com/tferr/Scripts#scripts
	https://imagej.net/doku.php?id=macro:roi_color_coder
	v221128: 1st version  f2f3: Updated stripKnownExtensionFromString function.v230615 updated addImageToStack function. f5: v230804 version of getResultsTableList and selectResultsWindow functions. F6: Updated indexOf functions. F13 : Replaced function: pad. F14: Updated getColorFromColorName function (012324). F15: updated function unCleanLabel.
	v250509: Initial fontSize is integer to match addNumber dp.
 */
macro "Pixel Color Coder with Labels" {
	macroL = "Pixel_Color_Coder_v250509.ijm";
	requires("1.47r");
	if (!checkForPluginNameContains("Fiji_Plugins")) exit("Sorry this macro requires some functions in the Fiji_Plugins package");
	/* Needs Fiji_pluings for autoCrop */
	saveSettings;
	close("*_Ramp"); /* cleanup: closes previous ramp windows */
	/* Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* Set the background to white */
	run("Colors...", "foreground=black background=white selection=yellow"); /* Set the preferred colors for these macros */
	setOption("BlackBackground", false);
	run("Appearance...", " "); if(is("Inverting LUT")) run("Invert LUT"); /* do not use Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background) https://imagej.net/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	switchIsOn = "false";
	activateIsOn = "false";
	selEType = selectionType;
	if (selEType>=0) {
		getSelectionBounds(selEX, selEY, selEWidth, selEHeight);
		selEX2 = selEX + selEWidth;
		selEY2 = selEY + selEHeight;
		if (selEWidth<10 || selEHeight<10){
			run("Select None"); /* assumed to be an accidental selection */
			selEType=-1;
		}
	}
	id = getImageID();	t=getTitle(); /* get id of image and title */
	screenH = screenHeight();
	maxMem = IJ.maxMemory();
	maxMemFactor = 100000000/maxMem;
	mem = IJ.currentMemory();
	mem /=1000000;
	startMemPC = mem*maxMemFactor;
	memFlushIncrement = 10;
	checkForUnits(); /* Required function */
	getPixelSize(unit, pixelWidth, pixelHeight);
	lcf = (pixelWidth+pixelHeight)/2; /* length conversion factor */
	checkForAnyResults();
	nRes = nResults;
	setBatchMode(true);
	tN = stripKnownExtensionFromString(unCleanLabel(t)); /* File.nameWithoutExtension is specific to last opened file, also remove special characters that might cause issues saving file */
	if (lengthOf(tN)>43) tNL = substring(tN,0,21) + "..." + substring(tN, lengthOf(tN)-21);
	else tNL = tN;
	imageHeight = getHeight(); imageWidth = getWidth();
	rampH = round(0.88 * imageHeight); /* suggest ramp slightly small to allow room for labels */
	fontSize = maxOf(8,round(rampH / 28)); /* default fonts size based on imageHeight */
	imageDepth = bitDepth(); /* required for shadows at different bit depths */
	headings = split(String.getResultsHeadings, "\t"); /* the tab specificity avoids problems with unusual column titles */
	/* To make it easier to find coordinates the heading are now filtered for X and Y */
	headingsWithX = filterArrayByContents(headings,newArray("x"),false);
	headingsWithY = filterArrayByContents(headings,newArray("y"),false);
	if (lengthOf(headingsWithX)<1 || lengthOf(headingsWithY)<1) restoreExit("Two XY coordinate sets are required \(a 'from' and a 'to'\); " + lengthOf(headingsWithX) + " header\(s\) with 'X' found, " + lengthOf(headingsWithY) + " header\(s\) with 'Y' found");
	headingsWithRange= newArray(lengthOf(headings));
	for (i=0; i<lengthOf(headings); i++) {
		resultsColumn = newArray(nRes);
		for (j=0; j<nRes; j++)
			resultsColumn[j] = getResult(headings[i], j);
		Array.getStatistics(resultsColumn, min, max, null, null);
		headingsWithRange[i] = headings[i] + ":  " + min + " - " + max;
	}
	if (headingsWithRange[0]==" :  Infinity - -Infinity")
		headingsWithRange[0] = "ID" + ":  1 - " + nRes; /* relabels ImageJ ID column */
	pixelParameters = newArray("ist","hick","ength","idth","readth", "iamter","eret");
	parameterIndex = 0;
	for (i=0; i<lengthOf(pixelParameters); i++)
		parameterIndex = maxOf(parameterIndex,indexOfArrayThatContains(headingsWithRange, pixelParameters[i]));
	/* create the dialog prompt */
	Dialog.create("Dialog #1: " + macroL);
		Dialog.addMessage("Image: " + tNL);
		Dialog.setInsets(6, 0, 0);
		Dialog.addChoice("Pixel X coordinate: ", headingsWithX, headingsWithX[0]);
		Dialog.addChoice("Pixel Y coordinate: ", headingsWithY, headingsWithY[0]);
		Dialog.setInsets(-1, 20, 6);
		if (lcf!=1){
			Dialog.addCheckbox("Divide coordinates by image calibration \("+lcf+"\)?", false);
			Dialog.addMessage("If the co-ordinates are not in pixels they will need to be divided by the scale factor");
		}
		Dialog.addChoice("Pixel color from: ", headingsWithRange, headingsWithRange[parameterIndex]);
		unitChoice = newArray("Auto", "Manual", unit, unit+"^2", "None", "pixels", "pixels^2", fromCharCode(0x00B0), "degrees", "radians", "%", "arb.");
		Dialog.addChoice("Unit \("+unit+"\) Label:", unitChoice, unitChoice[0]);
		// Dialog.setInsets(-40, 197, -5);
		// Dialog.addMessage("Auto based on\nselected parameter");
		luts=getLutsList();
		Dialog.addChoice("LUT:", luts, luts[0]);
		Dialog.setInsets(0, 120, 0);
		Dialog.addCheckbox("Reverse LUT?", false);
		Dialog.setInsets(6, 0, 6);
		defaultR = "Current Selection";
		if (selEType>=0) restrictions =  newArray("No", "Current Selection", "New Selection");
		else {
			restrictions = newArray("No", "New Selection");
			defaultR = "No";
		}
		Dialog.addRadioButtonGroup("Restrict Pixels to Area?", restrictions, 1, restrictions.length, defaultR);
		Dialog.addCheckbox("Overwrite Active Image?",false);
		Dialog.addCheckbox("Draw pixels on a white background",false);
		Dialog.addNumber("Line width \(pixel colored as rectangles\)",1,0,4,"pixels");
		Dialog.addRadioButtonGroup("Pixel addition sequence by value?", newArray("No", "Ascending", "Descending"),1,3,"Ascending");
		Dialog.addCheckbox("Make Animation Stack?",false);
	Dialog.show;
		pixelX = Dialog.getChoice();
		pixelY = Dialog.getChoice();
		ccf = 1;
		useLCF = false;
		if (lcf!=1) useLCF = Dialog.getCheckbox();
		if (useLCF) ccf = lcf;
		parameterWithLabel= Dialog.getChoice();
		parameter = substring(parameterWithLabel, 0, indexOf(parameterWithLabel, ":  "));
		unitLabel = Dialog.getChoice();
		lut = Dialog.getChoice();
		revLut = Dialog.getCheckbox();
		restrictPixels = Dialog.getRadioButton();
		overwriteImage = Dialog.getCheckbox();
		pixelsOnWhiteBG = Dialog.getCheckbox();
		lineWidth = Dialog.getNumber();
		drawSequence = Dialog.getRadioButton();
		makeAnimStack = Dialog.getCheckbox();
	/* end of format menu */
	if (makeAnimStack){
		Dialog.create("Animation options " + tN);
		Dialog.addCheckbox("Animation: Pixels color-coded on white\(transp\) frames?",false); /* Using individual non-disposing pixels can reduce the size of gif animation files */
		Dialog.addNumber(nRes + " pixels, draw", maxOf(1,round(nRes/1000)), 0, 3, "pixels\/animation frame");
		Dialog.show();
		animPixelsOnWhite = Dialog.getCheckbox();
		pixelsPerFrame = maxOf(1,Dialog.getNumber());
	}
	values = Table.getColumn(parameter);
	Array.getStatistics(values, arrayMin, arrayMax, arrayMean, arraySD);
	/*	Determine parameter label */
	parameterLabel = parameter;
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
	parameterLabel = stripUnitFromString(parameter);
	unitLabel = cleanLabel(unitLabel);
	rampParameterLabel = cleanLabel(parameterLabel);
	dP = autoCalculateDecPlaces(arrayMin,arrayMax,10);
	Dialog.create("Ramp - Legend Options");
		Dialog.addString("Ramp Parameter Label:", rampParameterLabel, 22);
		Dialog.addString("Ramp Unit:", unitLabel, 5);
		Dialog.addString("Ramp Range:", arrayMin + "-" + arrayMax, 11);
		Dialog.setInsets(-35, 248, 0);
		Dialog.addMessage("Full: " + arrayMin + "-" + arrayMax);
		Dialog.addString("Color Coded Range:", arrayMin + "-" + arrayMax, 11);
		Dialog.setInsets(-35, 248, 0);
		Dialog.addMessage("Full: " + arrayMin + "-" + arrayMax);
		Dialog.addNumber("No. of intervals:", 10, 0, 3, "Defines major ticks/label spacing");
		Dialog.addNumber("Minor tick intervals:", 5, 0, 3, "5 would add 4 ticks between labels ");
		Dialog.addChoice("Decimal places:", newArray(dP, "Auto", "Manual", "Scientific", "0", "1", "2", "3", "4"), dP);
		Dialog.addChoice("LUT height \(pxls\):", newArray(rampH, 128, 256, 512, 1024, 2048, 4096), rampH);
		// Dialog.setInsets(-38, 250, 0); /* (top, left, bottom) */
		// Dialog.addMessage(rampH + " pxls suggested\nby image height");
		fontStyleChoice = newArray("bold", "bold antialiased", "italic", "italic antialiased", "bold italic", "bold italic antialiased", "unstyled");
		Dialog.addChoice("Font style:", fontStyleChoice, fontStyleChoice[1]);
		fontNameChoice = getFontChoiceList();
		Dialog.addChoice("Font name:", fontNameChoice, fontNameChoice[0]);
		Dialog.addNumber("Font_size \(height\):", fontSize, 0, 3, "pxls");
		// Dialog.setInsets(-25, 205, 0);
		Dialog.addCheckbox("Draw tick marks", true);
		// Dialog.setInsets(4, 120, 0);
		Dialog.addCheckbox("Force rotated legend label", false);
		Dialog.addCheckbox("Add thin lines at true minimum and maximum if different", false);
		Dialog.addCheckbox("Add thin lines at true mean and " + fromCharCode(0x00B1) + " SD", false);
		Dialog.addNumber("Thin line length:", 50, 0, 3, "\(% of length tick length\)");
		Dialog.addNumber("Thin line label font:", 70, 0, 3, "% of font size");
	Dialog.show;
		rampParameterLabel = cleanLabel(Dialog.getString);
		unitLabel = cleanLabel(Dialog.getString);
		rangeS = Dialog.getString; /* changed from original to allow negative values - see below */
		rangeCoded = Dialog.getString; /* Range to be coded */
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
		minmaxLines = Dialog.getCheckbox;
		statsRampLines = Dialog.getCheckbox;
		statsRampTicks = Dialog.getNumber;
		thinLinesFontSTweak= Dialog.getNumber;
	/* Some more cleanup after last run */
	if (makeAnimStack) closeImageByTitle("animStack");
	if (!overwriteImage) closeImageByTitle(tN+"_Pixels");
	if (rotLegend && (rampHChoice==rampH)) rampH = imageHeight - 2 * fontSize; /* tweak automatic height selection for vertical legend */
	else rampH = rampHChoice;
	fontSR2 = fontSize * thinLinesFontSTweak/100;
	if (restrictPixels=="New Selection") {
		if (is("Batch Mode")==true) setBatchMode(false); /* Does not accept interaction while batch mode is on */
		setTool("rectangle");
		msgtitle="Restricted Range of Pixels";
		msg = "Draw a box in the image to which you want the Pixels restricted";
		waitForUser(msgtitle, msg);
		getSelectionBounds(selEX, selEY, selEWidth, selEHeight);
		selEX2 = selEX + selEWidth;
		selEY2 = selEY + selEHeight;
		if (is("Batch Mode")==false) setBatchMode(true);	/* toggle batch mode back on */
	}
	rampLW = maxOf(1, round(rampH/512)); /* ramp line width with a minimum of 1 pixel */
	minmaxLW = round(rampLW / 4); /* line widths for ramp stats */
	run("Select None");
	/* get values for chosen parameter */
	if (drawSequence=="No") drawOrder = Array.getSequence(nRes);
	else drawOrder = Array.rankPositions(values);
	if (drawSequence=="Descending") drawOrder = Array.reverse(drawOrder);
	range = split(rangeS, "-");
	if (lengthOf(range)==1) {
		min= NaN; max= parseFloat(range[0]);
	} else {
		min= parseFloat(range[0]); max= parseFloat(range[1]);
	}
	if (indexOf(rangeS, "-")==0) min = 0 - min; /* checks to see if min is a negative value (lets hope the max isn't). */
	codedRange = split(rangeCoded, "-");
	if (lengthOf(codedRange)==1) {
		minCoded = NaN; maxCoded = parseFloat(codedRange[0]);
	} else {
		minCoded = parseFloat(codedRange[0]); maxCoded = parseFloat(codedRange[1]);
	}
	if (indexOf(rangeCoded, "-")==0) minCoded = 0 - minCoded; /* checks to see if min is a negative value (lets hope the max isn't). */
	if (isNaN(min)) min = arrayMin;
	if (isNaN(max)) max = arrayMax;
	if (isNaN(minCoded)) minCoded = arrayMin;
	if (isNaN(maxCoded)) maxCoded = arrayMax;
	/*	Create LUT-map legend	*/
	rampTBMargin = 2 * fontSize;
	rampW = round(rampH/8);
	canvasH = round(2 * rampTBMargin + rampH);
	canvasW = round(rampH/2);
	tickL = round(rampW/4);
	if (statsRampLines || minmaxLines) tickL = round(tickL/2); /* reduce tick length to provide more space for inside label */
	tickLR = round(tickL * statsRampTicks/100);
	getLocationAndSize(imgx, imgy, imgwidth, imgheight);
	call("ij.gui.ImageWindow.setNextLocation", imgx+imgwidth, imgy);
	newImage(tN + "_" + parameterLabel +"_Ramp", "8-bit ramp", rampH, rampW, 1);
	/* ramp color/gray range is horizontal only so must be rotated later */
	if (revLut) run("Flip Horizontally");
	tR = getTitle; /* short variable label for ramp */
	pixelColors = loadLutColors(lut);/* load the LUT as a hexColor array: requires function */
	/* continue the legend design */
	if(lut!="Grays") run("RGB Color"); /* converts ramp to RGB if not using grays only */
	setColor(0, 0, 0);
	setBackgroundColor(255, 255, 255);
	setFont(fontName, fontSize, fontStyle);
	setLineWidth(rampLW*2);
	autoUpdate(true);
	if (ticks) {
		drawRect(0, 0, rampH, rampW);
		/* The next steps add the top and bottom ticks */
		rampWT = rampW + 2*rampLW;
		run("Canvas Size...", "width=&rampH height=&rampWT position=Top-Center");
		drawLine(0, rampW-1, 0,  rampW-1 + 2*rampLW); /* left/bottom tick - remember coordinate range is one less then max dimension because coordinates start at zero */
		drawLine(rampH-1, rampW-1, rampH-1, rampW + 2*rampLW - 1); /* right/top tick */
	}
	run("Rotate 90 Degrees Left");
	run("Canvas Size...", "width=&canvasW height=&canvasH position=Center-Left");
	if (dpChoice=="Auto")
		decPlaces = autoCalculateDecPlaces(min, max, numLabels);
	else if (dpChoice=="Manual")
		decPlaces=getNumber("Choose Number of Decimal Places", 0);
	else if (dpChoice=="Scientific")
		decPlaces = -1;
	else decPlaces = dpChoice;
	if (parameter=="Object") decPlaces = 0; /* This should be an integer */
	/*
	draw ticks and values */
	step = rampH;
	if (numLabels>2) step /= (numLabels-1);
	setLineWidth(rampLW);
	/* now to see if the selected range values are within 99.5% of actual */
	if (((0.995*min)>arrayMin) || (max<(0.995*arrayMax))) minmaxOOR = true;
	else minmaxOOR = false;
	if ((min<(0.995*arrayMin)) || ((0.995*max)>arrayMax)) minmaxIOR = true;
	else minmaxIOR = false;
	if (minmaxIOR && minmaxLines) minmaxLines = true;
	else minmaxLines = false;
	for (i=0; i<numLabels; i++) {
		yPos = rampH + rampTBMargin - i*step -1; /* minus 1 corrects for coordinates starting at zero */
		rampLabel = min + (max-min)/(numLabels-1) * i;
		rampLabelString = removeTrailingZerosAndPeriod(d2s(rampLabel,decPlaces));
		if (minmaxIOR) {
			/*Now add overrun text labels at the top and/or bottom of the ramp if the true data extends beyond the ramp range */
			if ((i==0) && (min>arrayMin)) {
				rampExt = removeTrailingZerosAndPeriod(d2s(arrayMin,decPlaces+1)); /* adding 1 to dp ensures that the range is different */
				rampLabelString = rampExt + "-" + rampLabelString;
			}if ((i==(numLabels-1)) && (max<arrayMax)) {
				rampExt = removeTrailingZerosAndPeriod(d2s(arrayMax,decPlaces+1));
				rampLabelString += "-" + rampExt;
			}
		}
		drawString(rampLabelString, rampW+4*rampLW, yPos+fontSize/1.5);
		if (ticks) {
			if ((i>0) && (i<(numLabels-1))) {
				setLineWidth(rampLW);
				drawLine(0, yPos, tickL, yPos);					/* left tick */
				drawLine(rampW-1-tickL, yPos, rampW, yPos);
				setLineWidth(rampLW/2);
				drawLine(rampW, yPos, rampW+rampLW, yPos); /* right tick extends over border slightly as subtle cross-tick */
			}
		}
	}
	/* draw minor ticks */
	if (ticks && (minorTicks>0)) {
		minorTickStep = step/minorTicks;
		for (i=0; i<numLabels*minorTicks; i++) {
			if ((i>0) && (i<(((numLabels-1)*minorTicks)))) {
				yPos = rampH + rampTBMargin - i*minorTickStep -1; /* minus 1 corrects for coordinates starting at zero */
				setLineWidth(maxOf(1,round(rampLW/2)));
				drawLine(0, yPos, tickL/3, yPos);					/* left minor tick */
				drawLine(rampW-tickL/3-1, yPos, rampW-1, yPos);		/* right minor tick */
				setLineWidth(rampLW); /* Rest line width */
			}
		}
	}
	/* end draw minor ticks */
	/*  now draw the additional ramp lines */
	if (minmaxLines || statsRampLines) {
		newImage("label_mask", "8-bit black", getWidth(), getHeight(), 1);
		setColor("white");
		if (minmaxLines) {
			if (min==max) restoreExit("Something terribly wrong with this range!");
			trueMaxFactor = (arrayMax-min)/(max-min);
			maxPos = rampTBMargin + (rampH * (1 - trueMaxFactor));
			trueMinFactor = (arrayMin-min)/(max-min);
			minPos = rampTBMargin + (rampH * (1 - trueMinFactor));
			if (trueMaxFactor<1) {
				setFont(fontName, fontSR2, fontStyle);
				stringY = round(maxOf(maxPos+0.75*fontSR2,rampTBMargin+0.75*fontSR2));
				drawString("Max", round((rampW-getStringWidth("Max"))/2), stringY);
				drawLine(rampLW, maxPos, tickLR, maxPos);
				drawLine(rampW-1-tickLR, maxPos, rampW-rampLW-1, maxPos);
			}
			if (trueMinFactor>0) {
				setFont(fontName, fontSR2, fontStyle);
				stringY = round(minOf(minPos+0.75*fontSR2,rampTBMargin+rampH-0.25*fontSR2));
				drawString("Min", (rampW-getStringWidth("Min"))/2, stringY);
				drawLine(rampLW, minPos, tickLR, minPos);
				drawLine(rampW-1-tickLR, minPos, rampW-rampLW-1, minPos);
			}
		}
		if (statsRampLines) {
			meanFactor = (arrayMean-min)/(max-min);
			plusSDFactor =  (arrayMean+arraySD-min)/(max-min);
			minusSDFactor =  (arrayMean-arraySD-min)/(max-min);
			meanPos = rampTBMargin + (rampH * (1 - meanFactor));
			plusSDPos = rampTBMargin + (rampH * (1 - plusSDFactor));
			minusSDPos = rampTBMargin + (rampH * (1 - minusSDFactor));
			meanFS = 0.9*fontSR2;
			setFont(fontName, meanFS, fontStyle);
			drawString("Mean", (rampW-getStringWidth("Mean"))/2, meanPos+0.75*meanFS);
			drawLine(rampLW, meanPos, tickLR, meanPos);
			drawLine(rampW-1-tickLR, meanPos, rampW-rampLW-1, meanPos);
			if (plusSDFactor<1) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("+SD", (rampW-getStringWidth("+SD"))/2, round(plusSDPos+0.75*fontSR2));
				drawLine(rampLW, plusSDPos, tickLR, plusSDPos);
				drawLine(rampW-1-tickLR, plusSDPos, rampW-rampLW-1, plusSDPos);
			}
			if (minusSDFactor>0) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("-SD", (rampW-getStringWidth("-SD"))/2, round(minusSDPos+0.75*fontSR2));
				drawLine(rampLW, minusSDPos, tickLR, minusSDPos);
				drawLine(rampW-1-tickLR, minusSDPos, rampW-rampLW-1, minusSDPos);
			}
		}
		/* use a mask to create black outline white text to stand out against ramp colors */
		rampOutlineStroke = round(rampLW/2);
		setThreshold(0, 128);
		setOption("BlackBackground", false);
		run("Convert to Mask");
		selectWindow(tR);
		run("Select None");
		getSelectionFromMask("label_mask");
		if (rampOutlineStroke>0) run("Enlarge...", "enlarge=&rampOutlineStroke pixel");
		setBackgroundFromColorName("black"); /* functionoutlineColor]") */
		run("Clear");
		run("Select None");
		getSelectionFromMask("label_mask");
		setBackgroundFromColorName("white");
		run("Clear");
		run("Select None");
		closeImageByTitle("label_mask");

		/* reset colors and font */
		setFont(fontName, fontSize, fontStyle);
		setColor(0,0,0);
	}
	/*
	parse symbols in unit and draw final label below ramp */
	rampUnitLabel = replace(unitLabel, fromCharCode(0x00B0), "degrees"); /* replace lonely ° symbol */
	if ((rampW>getStringWidth(rampUnitLabel)) && (rampW>getStringWidth(rampParameterLabel)) && !rotLegend) { /* can center align if labels shorter than ramp width */
		if (rampParameterLabel!="") drawString(rampParameterLabel, round((rampW-(getStringWidth(rampParameterLabel)))/2), round(1.5*fontSize));
		if (rampUnitLabel!="") drawString(rampUnitLabel, round((rampW-(getStringWidth(rampUnitLabel)))/2), round(canvasH-0.5*fontSize));
	}
	else { /* need to left align if labels are longer and increase distance from ramp */
		autoCropGuessBackgroundSafe(); /* Use function that turns batch mode off and on */
		getDisplayedArea(null, null, canvasW, canvasH);
		run("Rotate 90 Degrees Left");
		canvasW = getHeight + round(2.5*fontSize);
		rampParameterLabel += ", " + rampUnitLabel;
		rampParameterLabel = expandLabel(rampParameterLabel);
		rampParameterLabel = replace(rampParameterLabel, fromCharCode(0x2009), " "); /* expand again now we have the space */
		rampParameterLabel = replace(rampParameterLabel, "px", "pixels"); /* expand "px" that was used to keep the Results columns narrower */
		run("Canvas Size...", "width=&canvasH height=&canvasW position=Bottom-Center");
		if (rampParameterLabel!="") drawString(rampParameterLabel, round((canvasH-(getStringWidth(rampParameterLabel)))/2), round(1.5*fontSize));
		run("Rotate 90 Degrees Right");
	}
	autoCropGuessBackgroundSafe(); /* Use function that turns batch mode off and on */
	getDisplayedArea(null, null, canvasW, canvasH);
	/* add padding to legend box - better than expanding crop selection as is adds padding to all sides */
	canvasW += round(imageWidth/150);
	canvasH += round(imageHeight/150);
	run("Canvas Size...", "width=&canvasW height=&canvasH position=Center");
	tR = getTitle;
	/* End of Ramp Creation */
	/* Beginning of Pixel Color-Coding */
	lcf=(pixelWidth+pixelHeight)/2; /* length conversion factor */
	/* iterate through the results table and code pixels with the ramp color */
	selectImage(id);
	if (is("Batch Mode")==false) setBatchMode(true);
	if (!overwriteImage) {
		if(pixelsOnWhiteBG) newImage(tN+"_Pixels", "RGB white", imageWidth, imageHeight, 1);
		else {
			copyImage(t,tN+"_Pixels");
			if (imageDepth==16 || imageDepth==32) run("8-bit"); /* No need for excessive bit depth here */
			if ((bitDepth()==8) && (lut!="Grays")) run("RGB Color"); /* converts image to RGB if not using grays only */
		}
	}
	workingT = getTitle();
	selectWindow(workingT);
	run("Select None");
	pixelsPerFrameCounter = 0;
	loopStart = getTime();
	makeFrames = newArray(nRes);
	frameCount = 0;
	pixelXs = Table.getColumn(pixelX);
	pixelYs = Table.getColumn(pixelY);
	for (d=0; d<nRes; d++) {
		i = drawOrder[d];
		showProgress(i, nRes);
		if (!isNaN(values[i]) && (values[i]>=minCoded) && (values[i]<=maxCoded)) {
			if (values[i]<=min)
				lutIndex= 0;
			else if (values[i]>max)
				lutIndex= 255;
			else if (!revLut)
				lutIndex= round(255 * (values[i] - min) / (max - min));
			else
				lutIndex= round(255 * (max - values[i]) / (max - min));
			setColor("#"+pixelColors[lutIndex]);
			X1 = pixelXs[i]/ccf;
			Y1 = pixelYs[i]/ccf;
			makeFrames[i] = false;
			if ((X1<=imageWidth) && (Y1<=imageHeight) ) { /* this allows you to crop image from top left if necessary */
				selectWindow(workingT);
				if 	(restrictPixels=="No") {
					drawRect(X1, Y1, lineWidth, lineWidth);
					makeFrames[i] = true;
					frameCount += 1;
				}
				else {
					if ((X1>=selEX) && (X1<=selEX2) && (Y1>=selEY) && (Y1<=selEY2)) {
						drawRect(X1, Y1, lineWidth, lineWidth);
						makeFrames[i] = true;
						frameCount += 1;
					}
				}
			}
		}
	}
	Dialog.create("Combine Labeled Image and Legend?");
		comboChoice = newArray("No");
		comboChoiceCurrent = newArray("Combine Ramp with Current", "Combine Ramp with New Image");
		comboChoiceScaled = newArray("Combine Scaled Ramp with Current", "Combine Scaled Ramp with New Image");
		comboChoiceCropped = newArray("Combine Scaled Ramp with New Image Cropped to Restricted Pixels");
		comboChoiceCropNewSelection = newArray("Combine Scaled Ramp with Image Cropped to Old or New Selection");
		if (canvasH>imageHeight || canvasH<(0.93*imageHeight)) comboChoice = Array.concat(comboChoice,comboChoiceScaled,comboChoiceCropNewSelection);
		else comboChoice = Array.concat(comboChoice,comboChoiceCurrent,comboChoiceCropNewSelection); /* close enough */
		if (restrictPixels!="No") {
			comboChoice = Array.concat(comboChoice,comboChoiceCropped,comboChoiceCropNewSelection);
			Dialog.addChoice("Combine labeled image and legend?", comboChoice, comboChoice[4]);
		}else Dialog.addChoice("Combine labeled image and legend?", comboChoice, comboChoice[2]);
	Dialog.show();
		createCombo = Dialog.getChoice();
	if (createCombo!="No") {
		comboImage = "temp_combo";
		rampScale =  getHeight()/canvasH; /* default to no scale */
		if (indexOf(createCombo, "Cropped")>0) {
			if (indexOf(createCombo, "New Selection")>0) {
				if (is("Batch Mode")==true) setBatchMode(false); /* Toggle batch mode off for user interaction */
				if (selEType>=0) makeRectangle(selEX, selEY, selEWidth, selEHeight);
				setTool("rectangle");
				msgtitle="Area selection";
				msg = "Draw a box in the image to which you want the output image restricted";
				waitForUser(msgtitle, msg);
				getSelectionBounds(selEX, selEY, selEWidth, selEHeight);
				if (is("Batch Mode")==false) setBatchMode(true); /* Toggle batch mode back on */
			}
			else makeRectangle(selEX, selEY, selEWidth, selEHeight);
			run("Duplicate...", "title=temp_combo");
			rampScale = getHeight()/canvasH;
		} else if (indexOf(createCombo, "New Image")>0){
			selectWindow(workingT);
			run("Duplicate...", "title=temp_combo");
			rampScale = getHeight()/canvasH;
		}
		comboH = getHeight();
		comboW = getWidth();
		if (indexOf(createCombo, "Scaled")<=0) rampScale =  1;
		selectWindow(tR);
		tRS = "scaled_ramp";
		run("Scale...", "x=&rampScale y=&rampScale interpolation=Bicubic average create title=&tRS");
		canvasH = getHeight(); /* update ramp height */
		canvasW = getWidth(); /* update ramp width */
		if (indexOf(createCombo, "Current")>0) {
			comboW = imageWidth+canvasW;
			comboH = imageHeight;
			comboImage = workingT;
		}
		else comboW += canvasW;
		selectWindow(comboImage);
		run("Canvas Size...", "width=&comboW height=&comboH position=Top-Left");
		makeRectangle(comboW-canvasW, round((comboH-canvasH)/2), canvasW, canvasH);
		run("Image to Selection...", "image=&tRS opacity=100");
		run("Flatten");
		if ((imageDepth==8) && (lut=="Grays")) run("8-bit"); /* restores gray if all gray settings */
		rename(workingT + "+ramp");
		closeImageByTitle(tRS);
		closeImageByTitle("temp_combo");
	}
	/* Start Animation Section */
	if(makeAnimStack) {
		reuseSelection = false;
		reusePixels = false;
		cX1 = 0;
		cY1 = 0;
		copyImage(t,"tempFrame1");
		if (imageDepth!=8 || lut!="Grays") run("RGB Color");
		if(animPixelsOnWhite) run("Max...", "value=254"); /* restrict max intensity to 254 so no transparent regions in the background image */
		Dialog.create("Crop Animation Frame?");
			Dialog.addCheckbox("Would you like to restrict the animation frames to a cropped area?", false);
			if (restrictPixels!="No") {
				Dialog.addCheckbox("Crop to restricted pixels area?", true);
				Dialog.addCheckbox("Use the same restricted " + frameCount + " pixels?", true);
			}
			Dialog.addCheckbox("Would you like to resize the animation frame to reduce memory load?", false);
			Dialog.addCheckbox("Would you like to add the scaled ramp to the right of the 1st frame?", true);
			Dialog.addRadioButtonGroup("Sequence frames by value?", newArray("No", "Ascending", "Descending"),1,3,"Ascending");
		Dialog.show;
			animCrop = Dialog.getCheckbox();
			if (restrictPixels!="No") {
				reuseSelection = Dialog.getCheckbox();
				reusePixels =  Dialog.getCheckbox();
			}
			animResize = Dialog.getCheckbox();
			addRamp = Dialog.getCheckbox();
			valueSort = Dialog.getRadioButton();
		if(animCrop) {
			if (reuseSelection) {
				cX1 = selEX; cY1 = selEY; cW = selEWidth;cH = selEHeight;
			}
			else {
				getLocationAndSize(tFx, tFy, tFWidth, tFHeight);
				OKZoom = 75*screenH/tFHeight;
				run("Set... ", "zoom="+OKZoom/10+" x=0 y=0"); /* Use zoom to hide image */
				selectWindow(t);
				if ((restrictPixels!="No") && (selEType>=0)) makeRectangle(selEX, selEY, selEWidth, selEHeight);
				msgtitle="Select area to crop for animation frames";
				if (restrictPixels!="No") msg = "Previous restricted pixels box shown";
				else msg = "Select an area in image window " + t + " for the animation frames";
				waitForUser(msgtitle, msg);
				getSelectionBounds(cX1, cY1, cW, cH);
				run("Select None");
				selectWindow("tempFrame1");
				run("Set... ", "zoom=&OKZoom x="+tFWidth/2+" y="+tFHeight/2); /* Use zoom to hide image */
			}
		}
		animScaleF = 1; /* Default to no scaling */
		if (animResize) {
			if (animCrop) scaleGuess = (round(10240/cW))/10;
			else scaleGuess = (round(10240/imageWidth))/10;
			Dialog.create("Scale Animation Frame?");
				if (animCrop) Dialog.addMessage("Current Frame Width: " + cW + "pixels");
				else Dialog.addMessage("Current Frame Width: " + imageWidth + "pixels");
				Dialog.addNumber("Choice of scale factor:", minOf(1,scaleGuess)); /* Limit to reduction only */
				// Dialog.addNumber("Choice of scale factor:", scaleGuess);
			Dialog.show;
			animScaleF = Dialog.getNumber();
		}
		/* Create first animation frame */
		selectWindow("tempFrame1");
		if(animCrop || animResize){
			if (animCrop){
				makeRectangle(cX1, cY1, cW, cH);
				run("Crop");
				run("Select None");
			}
			if(animResize) run("Scale...", "x=&animScaleF y=&animScaleF interpolation=Bicubic average create title=frame1");
			else run("Duplicate...", "title=frame1");
		}
		else copyImage("tempFrame1", "frame1");
		closeImageByTitle("tempFrame1"); /* requires v181002 version */
		animFrameHeight = getHeight;
		animFrameNoRampWidth = getWidth;
		if(addRamp){
			selectWindow(tR);
			tRA = "Scaled_Anim_Ramp";
			selectWindow(tR);
			canvasH = getHeight(); /* update ramp height */
			rampScale = animFrameHeight/canvasH;
			run("Scale...", "x=&rampScale y=&rampScale interpolation=Bicubic average create title=&tRA");
			selectWindow(tRA);
			sarW = getWidth;
			sarH = getHeight;
			animComboW = sarW + animFrameNoRampWidth;
			selectWindow("frame1");
			copyImage("frame1","temp_combo");
			selectWindow("temp_combo");
			run("Canvas Size...", "width=&animComboW height=&animFrameHeight position=Top-Left");
			makeRectangle(animFrameNoRampWidth, round((animFrameHeight-sarH)/2), sarW, sarH);
			setBatchMode("exit & display");
			selectWindow("temp_combo"); /* voodoo pixel seems to help */
			wait(10);
			run("Image to Selection...", "image=Scaled_Anim_Ramp opacity=100");
			run("Flatten");
			setBatchMode(true);
			if ((imageDepth==8) && (lut=="Grays")) run("8-bit"); /* restores gray if all gray settings */
			rename("frame1_combo");
			closeImageByTitle(tRA);
			closeImageByTitle("temp_combo");
			closeImageByTitle("frame1");
			rename("frame1");
		}
		animFrameWidth = getWidth;
		/* End of creation of initial animStack frame */
		copyImage("frame1", "animStack");

		if (valueSort!="No") valueRank = Array.rankPositions(values);
		if (valueSort=="Descending")	valueRank = Array.reverse(valueRank);

		/* Create array holders for sorted values */
		animX1 = newArray(nRes);
		animY1 = newArray(nRes);
		animMakeFrame = newArray(nRes);
		pixelCounter = 0;
		/* Determine pixels to be drawn for animation and their order */
		for (i=0; i<nRes; i++) {
			if (valueSort!="No") j = valueRank[i];
			else j = i;
			X1 = animScaleF * ((pixelXs[j]/ccf)-cX1);
			Y1 = animScaleF * ((pixelYs[j]/ccf)-cY1);
			if (reusePixels) reusePixel = makeFrames[j];
			else reusePixel = true;
			if ((X1>=0) && (Y1>=0) && reusePixel){
				animMakeFrame[j] = true;
				pixelCounter += 1;
			}
			else animMakeFrame[j] = false;
			animX1[j] = X1;
			animY1[j] = Y1;
		}
		pixelsPerFrameCounter = 0;
		pixelsDrawn = 0;
		frameCount = 0;
		lastFrameValue = arrayMax + 1; /* Just make sure this is not in the value set */
		loopStart = getTime();
		previousUpdateTime = loopStart;
		animPixelWidth = maxOf(1,animScaleF*pixelWidth);
		setLineWidth(animPixelWidth);
		progressWindowTitleS = "Animation_Frame_Creation_Progress";
		progressWindowTitle = "[" + progressWindowTitleS + "]";
		run("Text Window...", "name=&progressWindowTitleS width=25 height=2 monospaced");
		eval("script","f = WindowManager.getWindow('"+progressWindowTitleS+"'); f.setLocation(50,20); f.setSize(550,150);");
		nextMemoryFlushPC = 50; /* 1st memory flush at 50% mem */
		for (i=0; i<nRes; i++) {
			if (valueSort!="No") j = valueRank[i];
			else j = i;
			if(animMakeFrame[j] && (values[j]>0) && (values[j]>=minCoded) && (values[j]<=maxCoded)){
				if (values[j]<=min)
					lutIndex= 0;
				else if (values[j]>max)
					lutIndex= 255;
				else if (!revLut)
					lutIndex= round(255 * (values[j] - min) / (max - min));
				else
					lutIndex= round(255 * (max - values[j]) / (max - min));
				setColor("#"+pixelColors[lutIndex]);
				if (!animPixelsOnWhite) { /* create animation frames pixels on original image */
					/* Keep adding to frame1 to create a cumulative image */
					selectWindow("frame1");
					drawRect(animX1[j], animY1[j], lineWidth, lineWidth);
					pixelsPerFrameCounter += 1;
					if (pixelsPerFrameCounter>=pixelsPerFrame || i==(nRes-1)) {
						if (values[j]!=lastFrameValue || i==(nRes-1)) {
							addImageToStack("animStack","frame1");
							pixelsPerFrameCounter = 0;
							lastFrameValue = values[j];
						}
					}
				}
				else {
					if (!isOpen("tempFrame")) newImage("tempFrame", "RGB white", animFrameWidth, animFrameHeight, 1);
					selectWindow("tempFrame");
					drawRect(animX1[j], animY1[j], lineWidth, lineWidth);
					pixelsPerFrameCounter += 1;
					if (pixelsPerFrameCounter>=pixelsPerFrame || i==(nRes-1)) { /* pixelCounter is the number of pixels in the full or restricted region and was determined earlier. This should trigger the last frame to be added */
						if (values[j]!=lastFrameValue || i==(nRes-1)) {
							addImageToStack("animStack","tempFrame");
							if(i<(nRes-1)) closeImageByTitle("tempFrame"); /* leave the last frame to add at the end */
							pixelsPerFrameCounter = 0; /* Reset pixels per frame counter so start new set of pixels in a new frame */
							lastFrameValue = values[j];
						}
					}
					run("Select None");
				}
				timeSinceUpdate = getTime()- previousUpdateTime;
				pixelsDrawn += 1;
				if((timeSinceUpdate>1000) && (pixelsDrawn>1)) {
					/* The time/memory window and memory flushing was add for some older PC with had limited memory but it is relatively time consuming so it is only updated ~ 1 second */
					timeTaken = getTime()-loopStart;
					timePerLoop = timeTaken/(i+1);
					timeLeft = (nRes-(i+1)) * timePerLoop;
					timeLeftM = floor(timeLeft/60000);
					timeLeftS = (timeLeft-timeLeftM*60000)/1000;
					totalTime = timeTaken + timeLeft;
					mem = IJ.currentMemory();
					mem /=1000000;
					memPC = mem * maxMemFactor;
					if (memPC > nextMemoryFlushPC) {
						run("Reset...", "reset=[Undo Buffer]");
						wait(100);
						run("Reset...", "reset=[Locked Image]");
						wait(100);
						call("java.lang.System.gc"); /* force a garbage collection */
						wait(100);
						flushedMem = IJ.currentMemory();
						flushedMem /=1000000;
						memFlushed = mem-flushedMem;
						memFlushedPC = (100/mem) * memFlushed;
						print(memFlushedPC + "% Memory flushed at " + timeTaken);
						nextMemoryFlushPC += memFlushIncrement;
					}
					if (memPC>90) restoreExit("Memory use has exceeded 90% of maximum memory");
					print(progressWindowTitle, "\\Update:"+timeLeftM+" m " +timeLeftS+" s to completion ("+(timeTaken*100)/totalTime+"%)\n"+getBar(timeTaken, totalTime)+"\n Current Memory Usage: "  + memPC + "% of MaxMemory: " + maxMem);
					previousUpdateTime = getTime();
				}
			}
		}
		if (isOpen("frame1")) addImageToStack("animStack","frame1");
		closeImageByTitle("frame1");
		if (isOpen("tempFrame")) addImageToStack("animStack","tempFrame");
		closeImageByTitle("tempFrame");
		eval("script","WindowManager.getWindow('"+progressWindowTitleS+"').close();");
	}
	run("Select None");
	/* End Animation Loop */
	if (createCombo!="No")closeImageByTitle(workingT);
	;
	call("java.lang.System.gc");
	/* display result		 */
	if (isOpen(id)) selectImage(id);
	restoreSettings;
	if ((restrictPixels!="No") && (selEType>=0)) makeRectangle(selEX, selEY, selEWidth, selEHeight);
	if (switchIsOn== "true") {
		hideResultsAs(tableUsed);
		restoreResultsFrom(hiddenResults);
	}
	if (activateIsOn== "true") {
		hideResultsAs(tableUsed);
	}
	setBatchMode("exit & display");
	showStatus("Pixel Color Coder completed.");
	beep(); wait(300); beep(); wait(300); beep();
	call("java.lang.System.gc");
	showStatus("Pixel Drawing Macro Finished");
}
	function getBar(p1, p2) {
		/* from https://imagej.net//macros/ProgressBar.txt */
        n = 20;
        bar1 = "--------------------";
        bar2 = "********************";
        index = round(n*(p1/p2));
        if (index<1) index = 1;
        if (index>n-1) index = n-1;
        return substring(bar2, 0, index) + substring(bar1, index+1, n);
	}
	/*
		   ( 8(|)	( 8(|)	ASC Functions	@@@@@:-)	@@@@@:-)
   */
	function addImageToStack(stackName,baseImage) {
		/* v230614: Added "Select None" */
		run("Copy");
		selectWindow(stackName);
		run("Add Slice");
		run("Paste");
		run("Select None");
		selectWindow(baseImage);
	}
	function autoCalculateDecPlaces(min,max,intervals){
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
	function checkForAnyResults() {
	/* v180918 uses getResultsTableList function
		v210715 fixes lengthOf(tableList) error
		REQUIRES restoreExit and therefore saveSettings
		v230804: Requires v230804 version of getResultsTableList
		*/
		funcL = "checkForAnyResults_v230804";
		if ((nResults==0) && ((getValue("results.count"))==0)){
			tableList = getResultsTableList(true);
			if (lengthOf(tableList)==0) {
				Dialog.create("No Results to Work With: " + funcL);
				Dialog.addMessage("No obvious tables open to work with  ¯|_(?)_/¯\nThis macro needs a table that includes the following columns in any order:\n   1.\) The parameter to color code with\n   2.\) 4 columns containing the to and from xy pixel coordinates");
				Dialog.addRadioButtonGroup("Do you want to: ", newArray("Open New Table", "Exit"), 1, 2, "Exit");
				Dialog.show();
				tableDecision = Dialog.getRadioButton();
				if (tableDecision=="Exit") restoreExit("GoodBye");
				else open();
				tableList = getResultsTableList(true);
			}
			tableList = Array.concat(newArray("none - exit"), tableList);
			Dialog.create("Select table to use...");
			Dialog.addChoice("Select Table to Activate", tableList,1);
			Dialog.show();
			tableUsed = Dialog.getChoice;
			if (tableUsed=="none - exit") restoreExit("Goodbye");
			activateIsOn = "true";
			restoreResultsFrom(tableUsed);
		}
		if ((getValue("results.count"))!=nResults && nResults!=0) {
			Dialog.create("Results Checker: " + funcL);
			Dialog.addMessage();
			Dialog.addRadioButtonGroup("There are more than one tables open; how do you want to proceed?", newArray("Swap Results with Other Table", "Close Results Table and Exit", "Exit"), 1, 3, "Swap Results with Other Table");
			Dialog.show();
			next = Dialog.getRadioButton;
			if (next=="Exit") restoreExit("Your have selected \"Exit\", Goodbye");
			else if (next=="Close Results Table and Exit") {
				closeNonImageByTitle("Results");
				restoreExit("Your have selected \"Exit\", perhaps now change name of your table to \"Results\"");
			}else {
				tableList = getResultsTableList(true);
				if (lengthOf(tableList)==0) restoreExit("Whoops, no other tables either");
				Dialog.create("Select table to analyze...");
				Dialog.addChoice("Select Table to Activate", tableList);
				Dialog.show();
				switchIsOn = "true";
				hideResultsAs(hiddenResults);
				tableUsed = Dialog.getChoice;
				restoreResultsFrom(tableUsed);
			}
		}
		else if ((getValue("results.count"))!=0 && nResults==0) {
			tableList = getResultsTableList(true);
			if (lengthOf(tableList)==0) restoreExit("Whoops, no other tables either");
			Dialog.create("Select table to analyze...");
			Dialog.addChoice("Select Table to Activate", tableList);
			Dialog.show();
			activateIsOn = "true";
			tableUsed = Dialog.getChoice;
			restoreResultsFrom(tableUsed);
		}
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
				if (endsWith(pluginFolderList[l], fS)) subFolderList = Array.concat(subFolderList,pluginFolderList[l]);
				else if (endsWith(pluginFolderList[l], "/")) subFolderList = Array.concat(subFolderList,pluginFolderList[l]); /* File.separator does not seem to be working here */
				else if (endsWith(toLowerCase(pluginFolderList[l]), ".jar") || endsWith(toLowerCase(pluginFolderList[l]), ".class")) pluginList = Array.concat(pluginList,toLowerCase(pluginFolderList[l]));
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
		v200604	fromCharCode(0x207B) removed as superscript hyphen not working reliably
		v220630 added degrees v220812 Changed Ångström unit code
		v231005 Weird Excel characters added, micron unit correction */
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
		if (indexOf(string,"mý")>1) string = substring(string, 0, indexOf(string,"mý")-1) + getInfo("micrometer.abbreviation") + fromCharCode(178);
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
	function closeNonImageByTitle(windowTitle) {
	/*  v200925 uses "while" instead of if so it can also remove duplicates
	*/
		while (isOpen(windowTitle)) {
			selectWindow(windowTitle);
			run("Close");
		}
	}
	function copyImage(source,target){
	/* 		NOTE: REQUIRES ASC restoreExit function which requires previous run of saveSettings */
		if (isOpen(source)) {
			imageCalculator("Copy create", source, source);
			rename(target);
		} else restoreExit("ImageWindow: " + source + " not found");
	}
	function expandLabel(string) {  /* Expands abbreviations typically used for compact column titles
		v200604	fromCharCode(0x207B) removed as superscript hyphen not working reliably
		v211102-v211103  Some more fixes and updated to match latest extended geometries
		v220808 replaces ° with fromCharCode(0x00B0)
		v230106 Added a few separation abbreviations */
		string = replace(string, "_cAR", "\(Corrected by Aspect Ratio\)");
		string = replace(string, "AR_", "Aspect Ratio: ");
		string = replace(string, "Cir_to_El_Tilt", "Circle Tilt based on Ellipse");
		string = replace(string, " Crl ", " Curl ");
		string = replace(string, "Da_Equiv","Diameter from Area \(Circular\)");
		string = replace(string, "Dp_Equiv","Diameter from Perimeter \(Circular\)");
		string = replace(string, "Dsph_Equiv","Diameter from Feret \(Spherical\)");
		string = replace(string, "Da", "Diam:area");
		string = replace(string, "Dp", "Diam:perim.");
		string = replace(string, "equiv", "equiv.");
		string = replace(string, "FeretAngle", "Feret Angle");
		string = replace(string, "Fbr", "Fiber");
		string = replace(string, "FiberThAnn", "Fiber Thckn. from Annulus");
		string = replace(string, "FiberLAnn", "Fiber Length from Annulus");
		string = replace(string, "FiberLR", "Fiber Length R");
		string = replace(string, "HSFR", "Hexagon Shape Factor Ratio");
		string = replace(string, "HSF", "Hexagon Shape Factor");
		string = replace(string, "Hxgn_", "Hexagon: ");
		string = replace(string, "Intfc_D", "Interfacial Density ");
		string = replace(string, "MinSepROI", "Minimum ROI Separation");
		string = replace(string, "MinSep", "Minimum Separation ");
		string = replace(string, "NN", "Nearest Neighbor ");
		string = replace(string, "Perim", "Perimeter");
		string = replace(string, "Perimetereter", "Perimeter"); /* just in case we already have a perimeter */
		string = replace(string, "Snk", "\(Snake\)");
		string = replace(string, "Raw Int Den", "Raw Int. Density");
		string = replace(string, "Rndnss", "Roundness");
		string = replace(string, "Rnd_", "Roundness: ");
		string = replace(string, "Rss1", "/(Russ Formula 1/)");
		string = replace(string, "Rss1", "/(Russ Formula 2/)");
		string = replace(string, "Sqr_", "Square: ");
		string = replace(string, "Squarity_AP","Squarity: from Area and Perimeter");
		string = replace(string, "Squarity_AF","Squarity: from Area and Feret");
		string = replace(string, "Squarity_Ff","Squarity: from Feret");
		string = replace(string, " Th ", " Thickness ");
		string = replace(string, "ThisROI"," this ROI ");
		string = replace(string, "Vol_", "Volume: ");
		string = replace(string, fromCharCode(0x00B0), "degrees");
		string = replace(string, "0-90", "0-90"+fromCharCode(0x00B0)); /* An exception to the above */
		string = replace(string, fromCharCode(0x00B0)+", degrees", fromCharCode(0x00B0)); /* That would be otherwise be too many degrees */
		string = replace(string, fromCharCode(0x00C2), ""); /* Remove mystery Â */
		// string = replace(string, "^-", fromCharCode(0x207B)); /* Replace ^- with superscript - Not reliable though */
		// string = replace(string, " ", fromCharCode(0x2009)); /* Use this last so all spaces converted */
		string = replace(string, "_", " ");
		string = replace(string, "  ", " ");
		return string;
	}
	function filterArrayByContents(inputArray,filterStrings,caseSensitive) {
		/* v221128 New version accepts and array of acceptable strings and also adds a case sensitivity option and assumes array expandability
		*/
		outputArray = newArray();
		pointsRowCounter = 0;
		for (i=0; i<lengthOf(inputArray); i++){
			input = inputArray[i];
			if (!caseSensitive) input = toLowerCase(input);
			for (j=0; j<lengthOf(filterStrings); j++){
				filter = filterStrings[j];	
				if (!caseSensitive) filter = toLowerCase(filter);
				if((indexOf(input,filter))>= 0) outputArray = Array.concat(outputArray,inputArray[i]);
			}
		}
		return outputArray;
	}
		/* ASC mod BAR Color Functions */

	function getColorArrayFromColorName(colorName) {
		/* v180828 added Fluorescent Colors
		   v181017-8 added off-white and off-black for use in gif transparency and also added safe exit if no color match found
		   v191211 added Cyan
		   v211022 all names lower-case, all spaces to underscores v220225 Added more hash value comments as a reference v220706 restores missing magenta
		   v230130 Added more descriptions and modified order.
		   v230908: Returns "white" array if not match is found and logs issues without exiting.
		   v240123: Removed duplicate entries: Now 53 unique colors 
		*/
		functionL = "getColorArrayFromColorName_v240123";
		cA = newArray(255,255,255); /* defaults to white */
		if (colorName == "white") cA = newArray(255,255,255);
		else if (colorName == "black") cA = newArray(0,0,0);
		else if (colorName == "off-white") cA = newArray(245,245,245);
		else if (colorName == "off-black") cA = newArray(10,10,10);
		else if (colorName == "light_gray") cA = newArray(200,200,200);
		else if (colorName == "gray") cA = newArray(127,127,127);
		else if (colorName == "dark_gray") cA = newArray(51,51,51);
		else if (colorName == "red") cA = newArray(255,0,0);
		else if (colorName == "green") cA = newArray(0,255,0);					/* #00FF00 AKA Lime green */
		else if (colorName == "blue") cA = newArray(0,0,255);
		else if (colorName == "cyan") cA = newArray(0, 255, 255);
		else if (colorName == "yellow") cA = newArray(255,255,0);
		else if (colorName == "magenta") cA = newArray(255,0,255);				/* #FF00FF */
		else if (colorName == "pink") cA = newArray(255, 192, 203);
		else if (colorName == "violet") cA = newArray(127,0,255);
		else if (colorName == "orange") cA = newArray(255, 165, 0);
		else if (colorName == "garnet") cA = newArray(120,47,64);				/* #782F40 */
		else if (colorName == "gold") cA = newArray(206,184,136);				/* #CEB888 */
		else if (colorName == "aqua_modern") cA = newArray(75,172,198);		/* #4bacc6 AKA "Viking" aqua */
		else if (colorName == "blue_accent_modern") cA = newArray(79,129,189); /* #4f81bd */
		else if (colorName == "blue_dark_modern") cA = newArray(31,73,125);	/* #1F497D */
		else if (colorName == "blue_honolulu") cA = newArray(0,118,182);		/* Honolulu Blue #006db0 */
		else if (colorName == "blue_modern") cA = newArray(58,93,174);			/* #3a5dae */
		else if (colorName == "gray_modern") cA = newArray(83,86,90);			/* bright gray #53565A */
		else if (colorName == "green_dark_modern") cA = newArray(121,133,65);	/* Wasabi #798541 */
		else if (colorName == "green_modern") cA = newArray(155,187,89);		/* #9bbb59 AKA "Chelsea Cucumber" */
		else if (colorName == "green_modern_accent") cA = newArray(214,228,187); /* #D6E4BB AKA "Gin" */
		else if (colorName == "green_spring_accent") cA = newArray(0,255,102);	/* #00FF66 AKA "Spring Green" */
		else if (colorName == "orange_modern") cA = newArray(247,150,70);		/* #f79646 tan hide, light orange */
		else if (colorName == "pink_modern") cA = newArray(255,105,180);		/* hot pink #ff69b4 */
		else if (colorName == "purple_modern") cA = newArray(128,100,162);		/* blue-magenta, purple paradise #8064A2 */
		else if (colorName == "jazzberry_jam") cA = newArray(165,11,94);
		else if (colorName == "red_n_modern") cA = newArray(227,24,55);
		else if (colorName == "red_modern") cA = newArray(192,80,77);
		else if (colorName == "tan_modern") cA = newArray(238,236,225);
		else if (colorName == "violet_modern") cA = newArray(76,65,132);
		else if (colorName == "yellow_modern") cA = newArray(247,238,69);
		/* Fluorescent Colors https://www.w3schools.com/colors/colors_crayola.asp */
		else if (colorName == "radical_red") cA = newArray(255,53,94);			/* #FF355E */
		else if (colorName == "wild_watermelon") cA = newArray(253,91,120);	/* #FD5B78 */
		else if (colorName == "shocking_pink") cA = newArray(255,110,255);		/* #FF6EFF Ultra Pink */
		else if (colorName == "razzle_dazzle_rose") cA = newArray(238,52,210);	/* #EE34D2 */
		else if (colorName == "hot_magenta") cA = newArray(255,0,204);			/* #FF00CC AKA Purple Pizzazz */
		else if (colorName == "outrageous_orange") cA = newArray(255,96,55);	/* #FF6037 */
		else if (colorName == "supernova_orange") cA = newArray(255,191,63);	/* FFBF3F Supernova Neon Orange*/
		else if (colorName == "sunglow") cA = newArray(255,204,51);			/* #FFCC33 */
		else if (colorName == "neon_carrot") cA = newArray(255,153,51);		/* #FF9933 */
		else if (colorName == "atomic_tangerine") cA = newArray(255,153,102);	/* #FF9966 */
		else if (colorName == "laser_lemon") cA = newArray(255,255,102);		/* #FFFF66 "Unmellow Yellow" */
		else if (colorName == "electric_lime") cA = newArray(204,255,0);		/* #CCFF00 */
		else if (colorName == "screamin'_green") cA = newArray(102,255,102);	/* #66FF66 */
		else if (colorName == "magic_mint") cA = newArray(170,240,209);		/* #AAF0D1 */
		else if (colorName == "blizzard_blue") cA = newArray(80,191,230);		/* #50BFE6 Malibu */
		else if (colorName == "dodger_blue") cA = newArray(9,159,255);			/* #099FFF Dodger Neon Blue */
		else IJ.log(colorName + " not found in " + functionL + ": Color defaulted to white");
		return cA;
	}
	function setBackgroundFromColorName(colorName) {
		colorArray = getColorArrayFromColorName(colorName);
		setBackgroundColor(colorArray[0], colorArray[1], colorArray[2]);
	}
	function getLutsList() {
		/* v180723 added check for preferred LUTs
			v210430 expandable array version   v211029 Added cividis.lut */
		defaultLuts= getList("LUTs");
		Array.sort(defaultLuts);
		lutsDir = getDirectory("LUTs");
		/* A list of frequently used LUTs for the top of the menu list . . . */
		preferredLutsList = newArray("Your favorite LUTS here", "cividis", "viridis-linearlumin", "silver-asc", "mpl-viridis", "mpl-plasma", "Glasbey", "Grays");
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
	function loadLutColors(lut) {
		/* v231207: Uses String.pad instead of function: pad */
		run(lut);
		getLut(reds, greens, blues);
		hexColors= newArray(256);
		for (i=0; i<256; i++) {
			r= toHex(reds[i]); g= toHex(greens[i]); b= toHex(blues[i]);
			hexColors[i]= ""+ String.pad(r, 2) + "" + String.pad(g, 2) + "" + String.pad(b, 2);
		}
		return hexColors;
	}
	/*
	End of ASC mod BAR Color Functions
	*/
  	function getFontChoiceList() {
		/*	v180723 first version
			v180828 Changed order of favorites. v190108 Longer list of favorites. v230209 Minor optimization.
			v230919 You can add a list of fonts that do not produce good results with the macro. 230921 more exclusions.
		*/
		systemFonts = getFontList();
		IJFonts = newArray("SansSerif", "Serif", "Monospaced");
		fontNameChoices = Array.concat(IJFonts,systemFonts);
		blackFonts = Array.filter(fontNameChoices, "([A-Za-z]+.*[bB]l.*k)");
		eBFonts = Array.filter(fontNameChoices,  "([A-Za-z]+.*[Ee]xtra.*[Bb]old)");
		uBFonts = Array.filter(fontNameChoices,  "([A-Za-z]+.*[Uu]ltra.*[Bb]old)");
		fontNameChoices = Array.concat(blackFonts, eBFonts, uBFonts, fontNameChoices); /* 'Black' and Extra and Extra Bold fonts work best */
		faveFontList = newArray("Your favorite fonts here", "Arial Black", "Myriad Pro Black", "Myriad Pro Black Cond", "Noto Sans Blk", "Noto Sans Disp Cond Blk", "Open Sans ExtraBold", "Roboto Black", "Alegreya Black", "Alegreya Sans Black", "Tahoma Bold", "Calibri Bold", "Helvetica", "SansSerif", "Calibri", "Roboto", "Tahoma", "Times New Roman Bold", "Times Bold", "Goldman Sans Black", "Goldman Sans", "Serif");
		/* Some fonts or font families don't work well with ASC macros, typically they do not support all useful symbols, they can be excluded here using the .* regular expression */
		offFontList = newArray("Alegreya SC Black", "Archivo.*", "Arial Rounded.*", "Bodon.*", "Cooper.*", "Eras.*", "Fira.*", "Gill Sans.*", "Lato.*", "Libre.*", "Lucida.*",  "Merriweather.*", "Montserrat.*", "Nunito.*", "Olympia.*", "Poppins.*", "Rockwell.*", "Tw Cen.*", "Wingdings.*", "ZWAdobe.*"); /* These don't work so well. Use a ".*" to remove families */
		faveFontListCheck = newArray(faveFontList.length);
		for (i=0,counter=0; i<faveFontList.length; i++) {
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
				if (endsWith(offFontList[j],".*")){
					if (startsWith(fontNameChoices[i], substring(offFontList[j], 0, indexOf(offFontList[j],".*")))){
						fontNameChoices = Array.deleteIndex(fontNameChoices, i);
						i = maxOf(0, i-1); 
					} 
					// fontNameChoices = Array.filter(fontNameChoices, "(^" + offFontList[j] + ")"); /* RegEx not working and very slow */
				} 
			} 
		}
		fontNameChoices = Array.concat(faveFontListCheck, fontNameChoices);
		for (i=0; i<fontNameChoices.length; i++) {
			for (j=i+1; j<fontNameChoices.length; j++)
				if (fontNameChoices[i]==fontNameChoices[j]) fontNameChoices = Array.deleteIndex(fontNameChoices, j);
		}
		return fontNameChoices;
	}
	function getResultsTableList(ignoreHistograms) {
		/* simply returns array of open results tables
		v200723: 1st version
		v201207: Removed warning message
		v230804: Adds boolean ignoreHistograms option */
		nonImageWindows = getList("window.titles");
		// if (nonImageWindows.length==0) exit("No potential results windows are open");
		if (nonImageWindows.length>0){
			resultsWindows = newArray();
			for (i=0; i<nonImageWindows.length; i++){
				selectWindow(nonImageWindows[i]);
				if(getInfo("window.type")=="ResultsTable")
				if (!ignoreHistograms) resultsWindows = Array.concat(resultsWindows,nonImageWindows[i]);
				else (indexOf(nonImageWindows[i],"Histogram")<0) resultsWindows = Array.concat(resultsWindows,nonImageWindows[i]);
			}
			return resultsWindows;
		}
		else return "";
	}
	function getSelectionFromMask(selection_Mask){
		batchMode = is("Batch Mode"); /* Store batch status mode before toggling */
		if (!batchMode) setBatchMode(true); /* Toggle batch mode off */
		tempTitle = getTitle();
		selectWindow(selection_Mask);
		run("Create Selection"); /* Selection inverted perhaps because the mask has an inverted LUT? */
		run("Make Inverse");
		selectWindow(tempTitle);
		run("Restore Selection");
		if (!batchMode) setBatchMode(false); /* Return to original batch mode setting */
	}
	function hideResultsAs(deactivatedResults) {
		if (isOpen("Results")) {  /* This swapping of tables does not increase run time significantly */
			selectWindow("Results");
			IJ.renameResults(deactivatedResults);
		}
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
	function indexOfArrayThatContains(array, value) {
		/* Like indexOfArray but partial matches possible
			v190423 Only first match returned */
		indexFound = -1;
		for (i=0; i<lengthOf(array); i++){
			if (indexOf(array[i], value)>=0){
				indexFound = i;
				i = lengthOf(array);
			}
		}
		return indexFound;
	}
	function memFlush(waitTime) {
		run("Reset...", "reset=[Undo Buffer]");
		wait(waitTime);
		run("Reset...", "reset=[Locked Image]");
		wait(waitTime);
		call("java.lang.System.gc"); /* force a garbage collection */
	}
	function removeTrailingZerosAndPeriod(string) {
	/* Removes any trailing zeros after a period
	v210430 totally new version: Note: Requires remTZeroP function
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
	function replaceImage(replacedWindow,window2) {
		/* v181005 Added descriptive failure for missing window2 */
		if (!isOpen(window2) restoreExit("replaceImage Function failure: Image " + window2 + " not open");
        if (isOpen(replacedWindow)) {
			selectWindow(replacedWindow);
			tempName = ""+replacedWindow+"Replaced";
			rename(tempName);
			selectWindow(window2);
			rename(replacedWindow);
			eval("script","WindowManager.getWindow('"+tempName+"').close();");
		}
		else copyImage(window2, replacedWindow); /* Use copyImage function */
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
	function restoreResultsFrom(deactivatedResults) {
		if (isOpen(deactivatedResults)) {
			selectWindow(deactivatedResults);
			IJ.renameResults("Results");
		}
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
			knownExts = newArray(".avi", ".csv", ".bmp", ".dsx", ".gif", ".jpg", ".jpeg", ".jp2", ".png", ".tif", ".txt", ".xlsx");
			knownExts = Array.concat(knownExts,knownExts,"_transp","_lzw");
			kEL = knownExts.length;
			for (i=0; i<kEL/2; i++) knownExts[i] = toUpperCase(knownExts[i]);
			chanLabels = newArray(" \(red\)"," \(green\)"," \(blue\)","\(red\)","\(green\)","\(blue\)");
			for (i=0,k=0; i<kEL; i++) {
				for (j=0; j<chanLabels.length; j++){ /* Looking for channel-label-trapped extensions */
					iChanLabels = lastIndexOf(string, chanLabels[j])-1;
					if (iChanLabels>0){
						preChan = substring(string,0,iChanLabels);
						postChan = substring(string,iChanLabels);
						while (indexOf(preChan,knownExts[i])>0){
							preChan = replace(preChan,knownExts[i],"");
							string =  preChan + postChan;
						}
					}
				}
				while (endsWith(string,knownExts[i])) string = "" + substring(string, 0, lastIndexOf(string, knownExts[i]));
			}
		}
		unwantedSuffixes = newArray(" ", "_","-");
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
		v210823 REQUIRES ASC function indexOfArray(array,string,default) for expanded "unitless" array.
		v220808 Replaces ° with fromCharCode(0x00B0).
		v230109 Expand px to pixels. Simplify angleUnits.
		v231005 Look and underscores replaced by spaces too.
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
			noUnits = newArray("Circ.","Slice","AR","Round","Solidity","Image_Name","PixelAR","ROI_name","ObjectN","AR_Box","AR_Feret","Rnd_Feret","Compact_Feret","Elongation","Thinnes_Ratio","Squarity_AP","Squarity_AF","Squarity_Ff","Convexity","Rndnss_cAR","Fbr_Snk_Crl","Fbr_Rss2_Crl","AR_Fbr_Snk","Extent","HSF","HSFR","Hexagonality");
			noUnitSs = newArray;
			for (i=0; i<noUnits.length; i++) noUnitSs[i] = replace(noUnits[i], "_", " ");
			angleUnits = newArray("Angle","FeretAngle","Cir_to_El_Tilt","0-90",fromCharCode(0x00B0),"0to90","degrees");
			angleUnitSs = newArray;
			for (i=0 ; i<angleUnits.length; i++) angleUnitSs[i] = replace(angleUnits[i], "_", " ");
			chooseUnits = newArray("Mean" ,"StdDev" ,"Mode" ,"Min" ,"Max" ,"IntDen" ,"Median" ,"RawIntDen" ,"Slice");
			if (string=="Area") unitLabel = imageUnit + fromCharCode(178);
			else if (indexOfArray(noUnits, string,-1)>=0) unitLabel = "None";
			else if (indexOfArray(noUnitSs, string,-1)>=0) unitLabel = "None";
			else if (indexOfArray(chooseUnits,string,-1)>=0) unitLabel = "";
			else if (indexOfArray(angleUnits,string,-1)>=0) unitLabel = fromCharCode(0x00B0);
			else if (indexOfArray(angleUnitSs,string,-1)>=0) unitLabel = fromCharCode(0x00B0);
			else if (string=="%Area") unitLabel = "%";
			else unitLabel = imageUnit;
			if (indexOf(unitLabel,"px")>=0) unitLabel = "pixels";
		}
		return unitLabel;
	}