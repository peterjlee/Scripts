/* Originally based on ROI_Color_Coder.ijm
	IJ BAR: https://github.com/tferr/Scripts#scripts
	http://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder
	Tiago Ferreira, v.5.2 2015.08.13 -	v.5.3 2016.05.1 + pjl mods 6/16-30/2016 to automate defaults and add labels to ROIs
	+ add ability to reverse LUT and also shows min and max values for all measurements to make it easier to choose a range 8/5/2016
	This version draws line between two sets of coordinates in a results table
	Stats and true min and max added to ramp 8/16-7/2016
	+ v170411 removes spaces from image names for compatibility with new image combinations
	+ v170914 Added garbage clean up as suggested by Luc LaLonde at LBNL.
	+ v180125 fixed "items" should be "nRes" error.
	+ v180725 Added system fonts to font list. Updated functions. Adds unit:pixel conversion option.
	+ v180831 Added check for Fiji_Plugins.
	+ v180912 Added options to crop animation frames to make it possible to create animations for very large data sets.
	+ v180918 Updated table functions.
	+ v180921 Can now sort values for the animation frames. Greatly reduced run time.
	+ v180926 Added coded range option.
	+ v180928 Fixed undef variable error.
	+ v181002-3 Minor fixes.
	+ v181004 Major overhaul of menus for better fit on smaller screen and to allow editing of labels. Also added option to change line drawing order.
	+ v181016-7 Restricted memory flush use to greatly improve speed. Fixed missing last animation frame. Original selection restored.
	+ v190327 Fixed accidental closure of output window when no combination chosen. Fixed variable ramp height. Fixed text location on ramp.
	+ v190423 Updated indexOfArrayThatContains function so it stops searching after finding the first match.
	+ v190506 Removed redundant function.
	+ v200123 Nested if that caused issues with dialog removed.
	+ v200707 Changed imageDepth variable name added macro label.
 */
macro "Line Color Coder with Labels"{
	macroL = "Line_Color_Coder_v200707";
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
	/*	The above should be the defaults but this makes sure (black particles on a white background) http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
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
	lcf=(pixelWidth+pixelHeight)/2; /* length conversion factor */
	checkForAnyResults();
	nRes = nResults;
	setBatchMode(true);
	tN = stripKnownExtensionFromString(unCleanLabel(t)); /* File.nameWithoutExtension is specific to last opened file, also remove special characters that might cause issues saving file */
	if (lengthOf(tN)>43) tNL = substring(tN,0,21) + "..." + substring(tN, lengthOf(tN)-21);
	else tNL = tN;
	imageHeight = getHeight(); imageWidth = getWidth();
	rampH = round(0.88 * imageHeight); /* suggest ramp slightly small to allow room for labels */
	fontSize = maxOf(8,rampH/28); /* default fonts size based on imageHeight */
	imageDepth = bitDepth(); /* required for shadows at different bit depths */
	/* Now variables specific to line drawing: */
	defaultLineWidth = round((imageWidth+imageHeight)/1000);
	headings = split(String.getResultsHeadings, "\t"); /* the tab specificity avoids problems with unusual column titles */
	/* To make it easier to find coordinates the heading are now filtered for X and Y */
	headingsWithX= filterArrayByContents(headings,"X", "x");
	if (lengthOf(headingsWithX)<2) restoreExit("Not enough x coordinates \(" + lengthOf(headingsWithX) + "\)");
	headingsWithY= filterArrayByContents(headings,"Y", "y");
	if (lengthOf(headingsWithY)<2) restoreExit("Not enough y coordinates \(" + lengthOf(headingsWithY) + "\)");
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
	lineParameters = newArray("ist","hick","ength","idth","readth", "iamter","eret");
	parameterIndex = 0;
	for (i=0; i<lengthOf(lineParameters); i++)
		parameterIndex = maxOf(parameterIndex,indexOfArrayThatContains(headingsWithRange, lineParameters[i]));
	/* create the dialog prompt */
	Dialog.create("Line Color Coder: " + macroL);
		Dialog.addMessage("Image: " + tNL);
		Dialog.setInsets(6, 0, 0);
		Dialog.addChoice("From x coordinate: ", headingsWithX, headingsWithX[0]);
		Dialog.addChoice("From y coordinate: ", headingsWithY, headingsWithY[0]);
		Dialog.addChoice("To x coordinate: ", headingsWithX, headingsWithX[1]);
		Dialog.addChoice("To y coordinate: ", headingsWithY, headingsWithY[1]);
		Dialog.setInsets(-1, 20, 6);
		if (lcf!=1) Dialog.addCheckbox("Divide coordinates by image calibration \("+lcf+"\)?", false); 
		Dialog.addChoice("Line color from: ", headingsWithRange, headingsWithRange[parameterIndex]);
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
		Dialog.addRadioButtonGroup("Restrict Lines to Area?", restrictions, 1, restrictions.length, defaultR); 
		Dialog.addCheckbox("Overwrite Active Image?",false);
		Dialog.addCheckbox("Draw coded lines on a white background",false);	
		Dialog.addRadioButtonGroup("Line draw sequence by value?", newArray("No", "Ascending", "Descending"),1,3,"Ascending");
		Dialog.addNumber("Line Width:", defaultLineWidth, 0, 4, "pixels");
		Dialog.addCheckbox("Make animation stack?",false);

	Dialog.show;
		fromX = Dialog.getChoice();
		fromY = Dialog.getChoice();
		toX = Dialog.getChoice();
		toY = Dialog.getChoice();
		ccf = 1;
		useLCF = false;
		if (lcf!=1) useLCF = Dialog.getCheckbox);
		if (useLCF) ccf = lcf;
		parameterWithLabel= Dialog.getChoice();
		parameter = substring(parameterWithLabel, 0, indexOf(parameterWithLabel, ":  "));
		unitLabel = Dialog.getChoice();
		lut = Dialog.getChoice();
		revLut = Dialog.getCheckbox();
		restrictLines = Dialog.getRadioButton();
		overwriteImage = Dialog.getCheckbox();
		linesOnWhiteBG = Dialog.getCheckbox();
		drawSequence = Dialog.getRadioButton();
		lineWidth = Dialog.getNumber();
		makeAnimStack = Dialog.getCheckbox();
	/* end of format menu */
	if (lineWidth<1) lineWidth = 1(); /* otherwise what is the point? */
	if (makeAnimStack){
		Dialog.create("Animation options " + tN);
		Dialog.addCheckbox("Animation: Lines drawn on white\(transp\) frames?",false); /* Using individual non-disposing lines can reduce the size of gif animation files */
		Dialog.addNumber(nRes + " lines, draw", round(nRes/1000), 0, 3, "lines\/animation frame");
		Dialog.show();	
		animLinesOnWhite = Dialog.getCheckbox();
		linesPerFrame = maxOf(1,Dialog.getNumber());
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
		if (!overwriteImage) closeImageByTitle(tN+"_Lines");
		
		if (rotLegend && (rampHChoice==rampH)) rampH = imageHeight - 2 * fontSize; /* tweak automatic height selection for vertical legend */
		else rampH = rampHChoice;
	
		fontSR2 = fontSize * thinLinesFontSTweak/100;		
		
		if (restrictLines=="New Selection") {
			if (is("Batch Mode")==true) setBatchMode(false); /* Does not accept interaction while batch mode is on */
			setTool("rectangle");
			msgtitle="Restricted Range of Lines";
			msg = "Draw a box in the image to which you want the lines restricted";
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
	lineColors = loadLutColors(lut);/* load the LUT as a hexColor array: requires function */
	/* continue the legend design */
	if(lut!="Grays") run("RGB Color"); /* converts ramp to RGB if not using grays only */
	setColor(0, 0, 0);
	setBackgroundColor(255, 255, 255);
	setFont(fontName, fontSize, fontStyle);
	setLineWidth(rampLW*2);
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
	/* Beginning of Line Drawing */
	
	lcf=(pixelWidth+pixelHeight)/2; /* length conversion factor */
	/* iterate through the results table and draw lines with the ramp color */
	selectImage(id);
	if (is("Batch Mode")==false) setBatchMode(true);
	setLineWidth(lineWidth);
	if (!overwriteImage) {
		if(linesOnWhiteBG) newImage(tN+"_Lines", "RGB white", imageWidth, imageHeight, 1);
		else {
			copyImage(t,tN+"_Lines");
			if (imageDepth==16 || imageDepth==32) run("8-bit"); /* No need for excessive bit depth here */
			if ((bitDepth()==8) && (lut!="Grays")) run("RGB Color"); /* converts image to RGB if not using grays only */
		}
	} 
	workingT = getTitle();
	selectWindow(workingT);
	run("Select None");
	linesPerFrameCounter = 0;
	loopStart = getTime();
	makeFrames = newArray(nRes);
	frameCount = 0;
	fromXs = Table.getColumn(fromX);
	fromYs = Table.getColumn(fromY);
	toXs = Table.getColumn(toX);
	toYs = Table.getColumn(toY);
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
			setColor("#"+lineColors[lutIndex]);
			X1 = fromXs[i]/ccf;
			Y1 = fromYs[i]/ccf;
			X2 = toXs[i]/ccf;
			Y2 = toYs[i]/ccf;
			makeFrames[i] = false;
			if ((X1<=imageWidth) && (X2<=imageWidth) && (Y1<=imageHeight) && (Y2 <imageHeight)) { /* this allows you to crop image from top left if necessary */
				selectWindow(workingT);
				if 	(restrictLines=="No") {
					drawLine(X1, Y1, X2, Y2);
					makeFrames[i] = true;
					frameCount += 1;
				}
				else {
					if ((X1>=selEX) && (X1<=selEX2) && (X2>=selEX) && (X2<=selEX2) && (Y1>=selEY) && (Y1<=selEY2) && (Y2>=selEY) && (Y2<=selEY2)) {
						drawLine(X1, Y1, X2, Y2);
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
		comboChoiceCropped = newArray("Combine Scaled Ramp with New Image Cropped to Restricted Lines");
		comboChoiceCropNewSelection = newArray("Combine Scaled Ramp with Image Cropped to Old or New Selection");
		if (canvasH>imageHeight || canvasH<(0.93*imageHeight)) comboChoice = Array.concat(comboChoice,comboChoiceScaled,comboChoiceCropNewSelection);
		else comboChoice = Array.concat(comboChoice,comboChoiceCurrent,comboChoiceCropNewSelection); /* close enough */
		if (restrictLines!="No") {
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
		reuseLines = false;
		cX1 = 0;
		cY1 = 0;
		copyImage(t,"tempFrame1");
		if (imageDepth!=8 || lut!="Grays") run("RGB Color");
		if(animLinesOnWhite) run("Max...", "value=254"); /* restrict max intensity to 254 so no transparent regions in the background image */
		Dialog.create("Crop Animation Frame?");
			Dialog.addCheckbox("Would you like to restrict the animation frames to a cropped area?", false);
			if (restrictLines!="No") {
				Dialog.addCheckbox("Crop to restricted lines area?", true);
				Dialog.addCheckbox("Use the same restricted " + frameCount + " lines?", true);
			}
			Dialog.addCheckbox("Would you like to resize the animation frame to reduce memory load?", false);
			Dialog.addCheckbox("Would you like to add the scaled ramp to the right of the 1st frame?", true);
			Dialog.addRadioButtonGroup("Sequence frames by value?", newArray("No", "Ascending", "Descending"),1,3,"Ascending");
		Dialog.show;
			animCrop = Dialog.getCheckbox();
			if (restrictLines!="No") {
				reuseSelection = Dialog.getCheckbox();
				reuseLines =  Dialog.getCheckbox();
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
				if ((restrictLines!="No") && (selEType>=0)) makeRectangle(selEX, selEY, selEWidth, selEHeight);
				msgtitle="Select area to crop for animation frames";
				if (restrictLines!="No") msg = "Previous restricted lines box shown";
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
			run("Image to Selection...", "image=Scaled_Anim_Ramp opacity=100");
			run("Flatten");
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
		animX2 = newArray(nRes);
		animY2 = newArray(nRes);
		animMakeFrame = newArray(nRes);
		lineCounter = 0;
		/* Determine lines to be drawn for animation and their order */
		for (i=0; i<nRes; i++) {
			if (valueSort!="No") j = valueRank[i];
			else j = i;
			X1 = animScaleF * ((fromXs[j]/ccf)-cX1);
			Y1 = animScaleF * ((fromYs[j]/ccf)-cY1);
			X2 = animScaleF * ((toXs[j]/ccf)-cX1);
			Y2 = animScaleF * ((toYs[j]/ccf)-cY1);
			if (reuseLines) reuseLine = makeFrames[j];
			else reuseLine = true;
			if ((X1>=0) && (Y1>=0) && (X2<=animFrameNoRampWidth) && (Y2<=animFrameHeight) && reuseLine){
				animMakeFrame[j] = true;
				lineCounter += 1;
			}
			else animMakeFrame[j] = false;
			animX1[j] = X1;
			animY1[j] = Y1;
			animX2[j] = X2;
			animY2[j] = Y2;
		}
		linesPerFrameCounter = 0;
		linesDrawn = 0;
		frameCount = 0;
		lastFrameValue = arrayMax + 1; /* Just make sure this is not in the value set */
		loopStart = getTime();
		previousUpdateTime = loopStart;
		animLineWidth = maxOf(1,animScaleF*lineWidth);
		setLineWidth(animLineWidth);
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
				setColor("#"+lineColors[lutIndex]);
				if (!animLinesOnWhite) { /* create animation frames lines on original image */
					/* Keep adding to frame1 to create a cumulative image */
					selectWindow("frame1");
					drawLine(animX1[j], animY1[j], animX2[j], animY2[j]);
					linesPerFrameCounter += 1;
					if (linesPerFrameCounter>=linesPerFrame || i==(nRes-1)) {
						if (values[j]!=lastFrameValue || i==(nRes-1)) {
							addImageToStack("animStack","frame1");
							linesPerFrameCounter = 0;
							lastFrameValue = values[j];
						}
					}
				}
				else {
					if (!isOpen("tempFrame")) newImage("tempFrame", "RGB white", animFrameWidth, animFrameHeight, 1);
					selectWindow("tempFrame");
					drawLine(animX1[j], animY1[j], animX2[j], animY2[j]);
					linesPerFrameCounter += 1;
					if (linesPerFrameCounter>=linesPerFrame || i==(nRes-1)) { /* lineCounter is the number of lines in the full or restricted region and was determined earlier. This should trigger the last frame to be added */
						if (values[j]!=lastFrameValue || i==(nRes-1)) {
							addImageToStack("animStack","tempFrame");
							if(i<(nRes-1)) closeImageByTitle("tempFrame"); /* leave the last frame to add at the end */
							linesPerFrameCounter = 0; /* Reset lines per frame counter so start new set of lines in a new frame */
							lastFrameValue = values[j];
						}
					}
					run("Select None");
				}
				timeSinceUpdate = getTime()- previousUpdateTime;
				linesDrawn += 1;
				if((timeSinceUpdate>1000) && (linesDrawn>1)) {
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
	if ((restrictLines!="No") && (selEType>=0)) makeRectangle(selEX, selEY, selEWidth, selEHeight);
	if (switchIsOn== "true") {
		hideResultsAs(tableUsed);
		restoreResultsFrom(hiddenResults);
	}
	if (activateIsOn== "true") {
		hideResultsAs(tableUsed);
	}
	setBatchMode("exit & display");
	showStatus("Line Color Coder completed.");																			 
	beep(); wait(300); beep(); wait(300); beep();
	call("java.lang.System.gc");
	showStatus("Line Drawing Macro Finished");
}	
	function getBar(p1, p2) {
		/* from https://imagej.nih.gov/ij//macros/ProgressBar.txt */
        n = 20;
        bar1 = "--------------------";
        bar2 = "********************";
        index = round(n*(p1/p2));
        if (index<1) index = 1;
        if (index>n-1) index = n-1;
        return substring(bar2, 0, index) + substring(bar1, index+1, n);
	}
	
	/*
		   ( 8(|)	( 8(|)	Functions	@@@@@:-)	@@@@@:-)
   */
	function addImageToStack(stackName,baseImage) {		
		run("Copy");
		selectWindow(stackName);
		run("Add Slice");
		run("Paste");
		selectWindow(baseImage);
	}
	function autoCalculateDecPlaces(min,max,numLabels){
		/* v181004 */
		step = (max-min)/numLabels;
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
	function checkForAnyResults() {
	/* v180918 uses getResultsTableList function */
		if ((nResults==0) && ((getValue("results.count"))==0)){
			tableList = getResultsTableList();
			if (lengthOf(tableList)==0) {
				Dialog.create("No Results to Work With");
				Dialog.addMessage("No obvious tables open to work with  ¯|_(?)_/¯\nThis macro needs a table that includes the following columns in any order:\n   1.\) The parameter to color code with\n   2.\) 4 columns containing the to and from xy pixel coordinates");
				Dialog.addRadioButtonGroup("Do you want to: ", newArray("Open New Table", "Exit"), 1, 2, "Exit"); 
				Dialog.show();
				tableDecision = Dialog.getRadioButton();
				if (tableDecision=="Exit") restoreExit("GoodBye");
				else open();
				tableList = getResultsTableList();
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
			Dialog.create("Results Checker");
			Dialog.addMessage();
			Dialog.addRadioButtonGroup("There are more than one tables open; how do you want to proceed?", newArray("Swap Results with Other Table", "Close Results Table and Exit", "Exit"), 1, 3, "Swap Results with Other Table"); 
			Dialog.show();
			next = Dialog.getRadioButton;
			if (next=="Exit") restoreExit("Your have selected \"Exit\", Goodbye");
			else if (next=="Close Results Table and Exit") {
				closeNonImageByTitle("Results");
				restoreExit("Your have selected \"Exit\", perhaps now change name of your table to \"Results\"");
			}else {
				tableList = getResultsTableList();
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
			tableList = getResultsTableList();
			if (lengthOf(list)==0) restoreExit("Whoops, no other tables either");
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
		/* If not in the root try the sub-folders */
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
	function closeNonImageByTitle(windowTitle) { /* obviously */
		if (isOpen(windowTitle)) {
			selectWindow(windowTitle);
			run("Close");
			}
	}
	function copyImage(source,target){
		if (isOpen(source)) {
			imageCalculator("Copy create", source, source);
			rename(target);
		} else restoreExit("ImageWindow: " + source + " not found");
	}
	function filterArrayByContents(inputArray,filterString1,filterString2) {
		arrayLengthCounter = 0; /* Reset row counter */
		outputArray = newArray(lengthOf(inputArray));
		pointsRowCounter = 0;
		for (a=0; a<lengthOf(outputArray); a++){
			if((indexOf(inputArray[a], filterString1))>= 0 || (indexOf(inputArray[a], filterString2))>= 0) {  /* Filter by intensity label */
					outputArray[pointsRowCounter] = inputArray[a];
					pointsRowCounter += 1;
			}
		}	
		outputArray = Array.slice(outputArray, 0, pointsRowCounter);
		return outputArray;
	}
		/* ASC mod BAR Color Functions */
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
	function pad(n) {
		n = toString(n);
		if(lengthOf(n)==1) n = "0"+n;
		return n;
	}
	function getLutsList() {
		/* v180723 added check for preferred LUTs */
		lutsCheck = 0;
		defaultLuts= getList("LUTs");
		Array.sort(defaultLuts);
		lutsDir = getDirectory("LUTs");
		/* A list of frequently used LUTs for the top of the menu list . . . */
		preferredLutsList = newArray("Your favorite LUTS here", "viridis-linearlumin", "silver-asc", "mpl-viridis", "mpl-plasma", "Glasbey", "Grays");
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
	End of ASC mod BAR Color Functions 
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
	function getResultsTableList() {
		/* v180925 added option to open new table if none is open */
		windowList = getList("window.titles");
		if (windowList.length==0) {
			Dialog.create("No open non-Window images.");
			Dialog.addCheckbox("Do you want to open a table with line coordinates or exit?", true);
			Dialog.show();
			if((Dialog.getCheckbox())==true) open();
			else restoreExit();
			windowList = getList("window.titles");
		}
		tableList = newArray(windowList.length);
		tableCounter=0;
		for (i=0; i<tableList.length; i++) {
			selectWindow(windowList[i]);
			if (getInfo("window.type")=="ResultsTable") {
				tableList[tableCounter]=windowList[i];
				tableCounter += 1;
			}
		}
		tableList = Array.trim(tableList, tableCounter);
		if (tableCounter==0)
			 showMessage("No Results table windows are open");
		else tableList = Array.trim(tableList, tableCounter);
		return tableList;
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
	function removeTrailingZerosAndPeriod(string) { /* Removes any trailing zeros after a period */
		while (endsWith(string,".0")) {
			string=substring(string,0, lastIndexOf(string, ".0"));
		}
		while(endsWith(string,".")) {
			string=substring(string,0, lastIndexOf(string, "."));
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
		/* 9/9/2017 added Garbage clean up suggested by Luc LaLonde - LBNL */
		restoreSettings(); /* Restore previous settings before exiting */
		setBatchMode("exit & display"); /* Probably not necessary if exiting gracefully but otherwise harmless */
		call("java.lang.System.gc");
		exit(message);
	}
	function restoreResultsFrom(deactivatedResults) {
		if (isOpen(deactivatedResults)) {
			selectWindow(deactivatedResults);		
			IJ.renameResults("Results");
		}
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
	- 041117 to remove spaces as well */
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
