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
 */
macro "Line Color Coder with Labels"{
	requires("1.47r");
	saveSettings;
	close("*_Ramp"); /* cleanup: closes previous ramp windows */
	run("Select None");
	/*
	Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* Set the background to white */
	run("Colors...", "foreground=black background=white selection=yellow"); /* Set the preferred colors for these macros */
	setOption("BlackBackground", false);
	run("Appearance...", " "); /* Do not use Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background)
		http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	switchIsOn = "false";
	activateIsOn = "false";
	selEType = selectionType; 
	if (selEType>=0) {
		getSelectionBounds(selEX, selEY, selEWidth, selEHeight);
		if (selEWidth<10 || selEHeight<10) selEWidth, selEHeight;
	}
	id = getImageID();	t=getTitle(); /* get id of image and title */	
	checkForUnits(); /* Required function */
	getPixelSize(unit, pixelWidth, pixelHeight);
	checkForAnyResults();
	nRes= nResults;
	setBatchMode(true);
	tN = stripExtensionsFromString(t); /* as in N=name could also use File.nameWithoutExtension but that is specific to last opened file */
	tN = unCleanLabel(tN); /* remove special characters to might cause issues saving file */
	imageHeight = getHeight(); imageWidth = getWidth();
	rampH = round(0.88 * imageHeight); /* suggest ramp slightly small to allow room for labels */
	fontSize = rampH/28; /* default fonts size based on imageHeight */
	originalImageDepth = bitDepth(); /* required for shadows at different bit depths */
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
	/* create the dialog prompt */
	Dialog.create("Line Color Coder: " + tN);
	Dialog.addMessage("This macro draws lines between sets of coordinates\nin a table and colors them according to an LUT");
	Dialog.addChoice("From x coordinate: ", headingsWithX, headingsWithX[0]);
	Dialog.addChoice("From y coordinate: ", headingsWithY, headingsWithY[0]);
	Dialog.addChoice("To x coordinate: ", headingsWithX, headingsWithX[1]);
	Dialog.addChoice("To y coordinate: ", headingsWithY, headingsWithY[1]);
	Dialog.addChoice("Line color from: ", headingsWithRange, headingsWithRange[1]);
	luts=getLutsList(); // still prefer this to new direct use of getList
	Dialog.addChoice("LUT:", luts, luts[0]);
	Dialog.addCheckbox("Reverse LUT?", false); 
	Dialog.setInsets(6, 0, 6);
	if (selEType>=0)
		Dialog.addRadioButtonGroup("Restrict Lines to Area?", newArray("No", "Current Selection", "New Selection"), 1, 3, "Current Selection"); 
	else Dialog.addRadioButtonGroup("Restrict Lines to Area?", newArray("No", "New Selection"), 1, 3, "No"); 
	Dialog.addCheckbox("Overwrite Active Image?", false); 
	Dialog.addCheckbox("Create a stack for animation?", false); 
	Dialog.addCheckbox("Animation: 1 line\/white frame?", false); /* Using individual non-disposing lines can reduce the size of gif animation files */
	Dialog.addNumber("Anim: Layers:", 10, 0, 3, "frames to skip");
	Dialog.addNumber("Line Width:", defaultLineWidth, 0, 4, "pixels");
	Dialog.setInsets(12, 0, 6);
	Dialog.addMessage("Legend \(ramp\):________________");
	unitChoice = newArray("Auto", "Manual", unit, unit+"^2", "None", "pixels", "pixels^2", fromCharCode(0x00B0), "degrees", "radians", "%", "arb.");
	Dialog.addChoice("Unit \("+unit+"\) Label:", unitChoice, unitChoice[0]);
	Dialog.setInsets(-42, 197, -5);
	Dialog.addMessage("Auto based on\nselected parameter");
	Dialog.addString("Range:", "AutoMin-AutoMax", 11);
	Dialog.setInsets(-35, 243, 0);
	Dialog.addMessage("(e.g., 10-100)");
	Dialog.addNumber("No. of intervals:", 10, 0, 3, "Defines major ticks/label spacing");
	Dialog.addNumber("Minor tick intervals:", 0, 0, 3, "5 would add 4 ticks between labels ");
	Dialog.addChoice("Decimal places:", newArray("Auto", "Manual", "Scientific", "0", "1", "2", "3", "4"), "Auto");
	Dialog.addChoice("LUT height \(pxls\):", newArray(rampH, 128, 256, 512, 1024, 2048, 4096), rampH);
	Dialog.setInsets(-38, 200, 0);
	Dialog.addMessage(rampH + " pxls suggested\nby image height");
	fontStyleChoice = newArray("bold", "bold antialiased", "italic", "italic antialiased", "bold italic", "bold italic antialiased", "unstyled");
	Dialog.addChoice("Font style:", fontStyleChoice, fontStyleChoice[1]);
	fontNameChoice = newArray("SansSerif", "Serif", "Monospaced");
	Dialog.addChoice("Font name:", fontNameChoice, fontNameChoice[0]);
	Dialog.addNumber("Font_size \(height\):", fontSize, 0, 3, "pxls");
	Dialog.setInsets(-25, 205, 0);
	Dialog.addCheckbox("Draw tick marks", true);
	Dialog.setInsets(4, 120, 0);
	Dialog.addCheckbox("Force rotated legend label", false);
	Dialog.addCheckbox("Add thin lines at true minimum and maximum if different", false);
	Dialog.addCheckbox("Add thin lines at true mean and � SD", false);
	Dialog.addNumber("Thin line length:", 50, 0, 3, "\(% of length tick length\)");
	Dialog.addNumber("Thin line label font:", 70, 0, 3, "% of font size");
	Dialog.show;
		fromX = Dialog.getChoice;
		fromY = Dialog.getChoice;
		toX = Dialog.getChoice;
		toY = Dialog.getChoice;
		parameterWithLabel= Dialog.getChoice;
		parameter= substring(parameterWithLabel, 0, indexOf(parameterWithLabel, ":  "));
		lut= Dialog.getChoice;
		revLut= Dialog.getCheckbox;
		restrictLines= Dialog.getRadioButton;
		overwriteImage= Dialog.getCheckbox;
		makeAnimStack= Dialog.getCheckbox;
		singleLine= Dialog.getCheckbox;
		frameSkip= Dialog.getNumber;
		lineWidth= Dialog.getNumber;
		if (lineWidth<1) lineWidth = 1; /* otherwise what is the point? */
		unitLabel = Dialog.getChoice();
		rangeS = Dialog.getString; /* changed from original to allow negative values - see below */
		numLabels = Dialog.getNumber + 1; /* The number of major ticks/labels is one more than the intervals */
		minorTicks = Dialog.getNumber; /* The number of major ticks/labels is one more than the intervals */
		dpChoice= Dialog.getChoice;
		rampChoice= parseFloat(Dialog.getChoice);
		fontStyle = Dialog.getChoice;
			if (fontStyle=="unstyled") fontStyle="";
		fontName= Dialog.getChoice;
		fontSize = Dialog.getNumber;
		ticks= Dialog.getCheckbox;
		rotLegend= Dialog.getCheckbox;
		minmaxLines = Dialog.getCheckbox;
		statsRampLines= Dialog.getCheckbox;
		statsRampTicks = Dialog.getNumber;
		thinLinesFontSTweak= Dialog.getNumber;
		
		/* Some more cleanup after last run */
		if (makeAnimStack) closeImageByTitle("animStack");
		if (!overwriteImage) closeImageByTitle(t+"_Lines");
		
		if (rotLegend && rampChoice==rampH) rampH = imageHeight - 2 * fontSize; /* tweak automatic height selection for vertical legend */
		else rampH = rampChoice;
	
		range = split(rangeS, "-");
		if (lengthOf(range)==1) {
			min= NaN; max= parseFloat(range[0]);
		} else {
			min= parseFloat(range[0]); max= parseFloat(range[1]);
		}
		if (indexOf(rangeS, "-")==0) min = 0 - min; /* checks to see if min is a negative value (lets hope the max isn't). */
		fontSR2 = fontSize * thinLinesFontSTweak/100;
		
		if (restrictLines=="New Selection") {
			if (is("Batch Mode")==true) setBatchMode(false); /* Does not accept interaction while batch mode is on */
			setTool("rectangle");
			msgtitle="Restricted Range of Lines";
			msg = "Draw a box in the image to which you want the lines restricted";
			waitForUser(msgtitle, msg);
			selEType = selectionType; 
			getSelectionBounds(selEX, selEY, selEWidth, selEHeight);
			selEType = selectionType; 
			if (is("Batch Mode")==false) setBatchMode(true);	/* toggle batch mode back on */
		}
		
		rampLW = maxOf(1, round(rampH/512)); /* ramp line width with a minimum of 1 pixel */
		minmaxLW = round(rampLW / 4); /* line widths for ramp stats */
		
	/* get values for chosen parameter */
	values = newArray(nRes);
	for (i=0; i<nRes; i++) values[i]= getResult(parameter,i);
	Array.getStatistics(values, arrayMin, arrayMax, arrayMean, arraySD);
	if (isNaN(min)) min= arrayMin;
	if (isNaN(max)) max= arrayMax;
	/*
	Determine parameter label */
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
	unitLabel= cleanLabel(unitLabel);
	/*	Create LUT-map legend	*/
	rampW = round(rampH/8); canvasH = round(4 * fontSize + rampH); canvasW = round(rampH/2); tickL = round(rampW/4);
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
	setColor(0, 0, 0);
	setBackgroundColor(255, 255, 255);
	setFont(fontName, fontSize, fontStyle);
	if (originalImageDepth!=8 || lut!="Grays") run("RGB Color"); /* converts ramp to RGB if not using grays only */
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
		decPlaces = autoCalculateDecPlaces(decPlaces);
	else if (dpChoice=="Manual") 
		decPlaces=getNumber("Choose Number of Decimal Places", 0);
	else if (dpChoice=="Scientific")
		decPlaces = -1;
	else decPlaces = dpChoice;
	if (parameter=="Object") decPlaces = 0; /* This should be an integer */
	/*
	draw ticks and values */
	rampOffset = (getHeight-rampH)/2; /* getHeight-rampH ~ 2 * fontSize */
	step = rampH;
	if (numLabels>2) step /= (numLabels-1);
	setLineWidth(rampLW);
	/* now to see if the selected range values are within 98% of actual */
	if (0.98*min>arrayMin || max<0.98*arrayMax) minmaxOOR = true;
	else minmaxOOR = false;
	if (min<0.98*arrayMin || 0.98*max>arrayMax) minmaxIOR = true;
	else minmaxIOR = false;
	if (minmaxIOR && minmaxLines) minmaxLines = true;
	else minmaxLines = false;
	for (i=0; i<numLabels; i++) {
		yPos = rampH + rampOffset - i*step -1; /* minus 1 corrects for coordinates starting at zero */
		rampLabel = min + (max-min)/(numLabels-1) * i;
		rampLabelString = removeTrailingZerosAndPeriod(d2s(rampLabel,decPlaces));
		if (minmaxIOR) {
			/*Now add overrun text labels at the top and/or bottom of the ramp if the true data extends beyond the ramp range */
			if (i==0 && min>arrayMin) {
				rampExt = removeTrailingZerosAndPeriod(d2s(arrayMin,decPlaces+1)); /* adding 1 to dp ensures that the range is different */
				rampLabelString = rampExt + "-" + rampLabelString; 
			}if (i==numLabels-1 && max<arrayMax) {
				rampExt = removeTrailingZerosAndPeriod(d2s(arrayMax,decPlaces+1));
				rampLabelString += "-" + rampExt; 
			}
		}
		drawString(rampLabelString, rampW+4*rampLW, round(yPos+fontSize/2));
		if (ticks) {
			if (i > 0 && i < numLabels-1) {
				setLineWidth(rampLW);
				drawLine(0, yPos, tickL, yPos);					/* left tick */
				drawLine(rampW-1-tickL, yPos, rampW, yPos);
				setLineWidth(rampLW/2);
				drawLine(rampW, yPos, rampW+rampLW, yPos); /* right tick extends over border slightly as subtle cross-tick */
			}
		}
	}
	/* draw minor ticks */
	if (ticks && minorTicks > 0) {
		minorTickStep = step/minorTicks;
		for (i=0; i<numLabels*minorTicks; i++) {
			if (i > 0 && i < (((numLabels-1)*minorTicks))) {
				yPos = rampH + rampOffset - i*minorTickStep -1; /* minus 1 corrects for coordinates starteding at zero */
				setLineWidth(round(rampLW/4));
				drawLine(0, yPos, tickL/4, yPos);					/* left minor tick */
										  
																																	  
				drawLine(rampW-tickL/4-1, yPos, rampW-1, yPos);		/* right minor tick */
				setLineWidth(rampLW); /* Rest line width */
			}
		}
	}
	/* end draw minor ticks */
	/*  now draw the additional ramp lines */
	if (minmaxLines || statsRampLines) {
		setBatchMode("exit and display");
		newImage("label_mask", "8-bit black", getWidth(), getHeight(), 1);
		setColor("white");
		if (minmaxLines) {
			if (min==max) restoreExit("Something terribly wrong with this range!");
			trueMaxFactor = (arrayMax-min)/(max-min);
			maxPos= round(fontSize/2 + (rampH * (1 - trueMaxFactor)) +1.5*fontSize);
			trueMinFactor = (arrayMin-min)/(max-min);
			minPos= round(fontSize/2 + (rampH * (1 - trueMinFactor)) +1.5*fontSize);
			if (trueMaxFactor<1) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("Max", round((rampW-getStringWidth("Max"))/2), round(maxPos+0.5*fontSR2));
				drawLine(rampLW, maxPos, tickLR, maxPos);
				drawLine(rampW-1-tickLR, maxPos, rampW-rampLW-1, maxPos);
			}
			if (trueMinFactor>0) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("Min", round((rampW-getStringWidth("Min"))/2), round(minPos+0.5*fontSR2));
				drawLine(rampLW, minPos, tickLR, minPos);
				drawLine(rampW-1-tickLR, minPos, rampW-rampLW-1, minPos);
			}
		}
		if (statsRampLines) {
			meanFactor = (arrayMean-min)/(max-min);
			plusSDFactor =  (arrayMean+arraySD-min)/(max-min);
			minusSDFactor =  (arrayMean-arraySD-min)/(max-min);
			meanPos= round(fontSize/2 + (rampH * (1 - meanFactor)) +1.5*fontSize);
			plusSDPos= round(fontSize/2 + (rampH * (1 - plusSDFactor)) +1.5*fontSize);
			minusSDPos= round(fontSize/2 + (rampH * (1 - minusSDFactor)) +1.5*fontSize);
			setFont(fontName, 0.9*fontSR2, fontStyle);
			drawString("Mean", round((rampW-getStringWidth("Mean"))/2), round(meanPos+0.4*fontSR2));
			drawLine(rampLW, meanPos, tickLR, meanPos);
			drawLine(rampW-1-tickLR, meanPos, rampW-rampLW-1, meanPos);	
			if (plusSDFactor<1) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("+SD", round((rampW-getStringWidth("+SD"))/2), round(plusSDPos+0.5*fontSR2));
				drawLine(rampLW, plusSDPos, tickLR, plusSDPos);
				drawLine(rampW-1-tickLR, plusSDPos, rampW-rampLW-1, plusSDPos);
			}
			if (minusSDFactor>0) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("-SD", round((rampW-getStringWidth("-SD"))/2), round(minusSDPos+0.5*fontSR2));
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
	run("Enlarge...", "enlarge=[rampOutlineStroke] pixel");
	setBackgroundFromColorName("black"); // functionoutlineColor]")
	run("Clear");
	run("Select None");
	getSelectionFromMask("label_mask");
	setBackgroundFromColorName("white");
	run("Clear");
	run("Select None");
	closeImageByTitle("label_mask");
		
	// reset colors and font
	setFont(fontName, fontSize, fontStyle);
	setColor(0,0,0);
	}
	/*
	parse symbols in unit and draw final label below ramp */
	rampParameterLabel= cleanLabel(parameterLabel);
	rampUnitLabel = replace(unitLabel, fromCharCode(0x00B0), "degrees"); // replace lonely � symbol
	if (rampW>getStringWidth(rampUnitLabel) && rampW>getStringWidth(rampParameterLabel) && !rotLegend) { // can center align if labels shorter than ramp width
		if (rampParameterLabel!="") drawString(rampParameterLabel, round((rampW-(getStringWidth(rampParameterLabel)))/2), round(1.5*fontSize));
		if (rampUnitLabel!="") drawString(rampUnitLabel, round((rampW-(getStringWidth(rampUnitLabel)))/2), round(canvasH-0.5*fontSize));
	}
	
	else { /* need to left align if labels are longer and increase distance from ramp */
		run("Auto Crop (guess background color)");
		getDisplayedArea(null, null, canvasW, canvasH);
		run("Rotate 90 Degrees Left");
		canvasW = getHeight + round(2.5*fontSize);
		rampParameterLabel += ", " + rampUnitLabel;
		rampParameterLabel = expandLabel(rampParameterLabel);
		rampParameterLabel = replace(rampParameterLabel, fromCharCode(0x2009), " "); /* expand again now we have the space */
		rampParameterLabel = replace(rampParameterLabel, "px", "pixels"); /* expand "px" that was used to keep the Results columns narrower */
		run("Canvas Size...", "width="+ canvasH +" height="+ canvasW+" position=Bottom-Center");
		if (rampParameterLabel!="") drawString(rampParameterLabel, round((canvasH-(getStringWidth(rampParameterLabel)))/2), round(1.5*fontSize));
		run("Rotate 90 Degrees Right");
	}
	// setBatchMode("exit & display");
	run("Auto Crop (guess background color)");
	setBatchMode("true");
	getDisplayedArea(null, null, canvasW, canvasH);
	/* add padding to legend box */
	canvasW += round(imageWidth/150);
	canvasH += round(imageHeight/150);
	run("Canvas Size...", "width="+ canvasW +" height="+ canvasH +" position=Center");
	tR = getTitle;
	lcf=(pixelWidth+pixelHeight)/2; /* length conversion factor */
	/* iterate through the results table and draw lines with the ramp color */
	selectImage(id);
	if (is("Batch Mode")==false) setBatchMode(true);
	setLineWidth(lineWidth);
	if (!overwriteImage)
		newImage(t+"_Lines", "RGB white", imageWidth, imageHeight, 1);
	workingT=getTitle();
	run("Select None");
	if (makeAnimStack) run("Duplicate...", "title=animStack");
	selectWindow(workingT);
	frameSkipCounter = 0;
	for (countNaN=0, i=0; i<nRes; i++) {
		// if (isNaN(values[i])) countNaN++;
		// if (values[i]=="End") i=nRes;
		if (!isNaN(values[i])) {
			if (values[i]<=min)
				lutIndex= 0;
			else if (values[i]>max)
				lutIndex= 255;
			else if (!revLut)
				lutIndex= round(255 * (values[i] - min) / (max - min));
			else 
				lutIndex= round(255 * (max - values[i]) / (max - min));
			// roiManager("Set Line Width", lineWidth);
			// roiManager("Set Color", alpha+lineColors[lutIndex]);
			setColor("#"+lineColors[lutIndex]);
			X1 = getResult(fromX,i);
			Y1 = getResult(fromY,i);
			X2 = getResult(toX,i);
			Y2 = getResult(toY,i);
			if (X1<=imageWidth && X2<=imageWidth && Y1<=imageHeight && Y2 <imageHeight) { // this allows you to crop image from top left if necessary
				if 	(restrictLines!="No") {
					selEX2 = selEX + selEWidth;
					selEY2 = selEY + selEHeight;
					if (X1>=selEX && X1<=selEX2 && X2>=selEX && X2<=selEX2 && Y1>=selEY && Y1<=selEY2 && Y2>=selEY && Y2<=selEY2) {	
						drawLine(getResult(fromX,i), getResult(fromY,i), getResult(toX,i), getResult(toY,i));
						frameSkipCounter += 1;
						if (frameSkipCounter==frameSkip) {
							if (makeAnimStack) {
								if (!singleLine)	addImageToStack("animStack",workingT);
								else {
									newImage("tempFrame", "RGB white", imageWidth, imageHeight, 1);
									drawLine(getResult(fromX,i), getResult(fromY,i), getResult(toX,i), getResult(toY,i));
									addImageToStack("animStack","tempFrame");
									closeImageByTitle("tempFrame");
								}
							}
						frameSkipCounter = 0;
						}
					}
				}
				else {
					drawLine(getResult(fromX,i), getResult(fromY,i), getResult(toX,i), getResult(toY,i));
					frameSkipCounter += 1;
					if (frameSkipCounter==frameSkip) {
						if (makeAnimStack) {
							if (!singleLine)	addImageToStack("animStack",workingT);
							else {
								newImage("tempFrame", "RGB white", imageWidth, imageHeight, 1);
								drawLine(getResult(fromX,i), getResult(fromY,i), getResult(toX,i), getResult(toY,i));
								addImageToStack("animStack","tempFrame");
								closeImageByTitle("tempFrame");
							}
						}
						frameSkipCounter = 0;
					}
				}
			}
		}
	}
	// tNC = getTitle();
	
	Dialog.create("Combine Labeled Image and Legend?");
		if (canvasH>imageHeight) comboChoice = newArray("No", "Combine Scaled Ramp with Current", "Combine Scaled Ramp with New Image");
		else if (canvasH>(0.93 * imageHeight)) comboChoice = newArray("No", "Combine Ramp with Current", "Combine Ramp with New Image"); // close enough
		else comboChoice = newArray("No", "Combine Scaled Ramp with Current", "Combine Scaled Ramp with New Image", "Combine Ramp with Current", "Combine Ramp with New Image");
		Dialog.addChoice("Combine labeled image and legend?", comboChoice, comboChoice[2]);
		Dialog.show();
	createCombo = Dialog.getChoice();
	if (createCombo!="No") {
		selectWindow(tR);
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Scaled Ramp with New Image") {
			rampScale = imageHeight/canvasH;
			run("Scale...", "x="+rampScale+" y="+rampScale+" interpolation=Bicubic average create title=scaled_ramp");
			canvasH = getHeight(); /* update ramp height */
		}
		srW = getWidth;
		comboW = srW + imageWidth;
		selectWindow(workingT);
		if (createCombo=="Combine Scaled Ramp with New Image" || createCombo=="Combine Ramp with New Image") run("Duplicate...", "title=temp_combo");
		run("Canvas Size...", "width="+comboW+" height="+imageHeight+" position=Top-Left");
		makeRectangle(imageWidth, round((imageHeight-canvasH)/2), srW, imageHeight);
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Scaled Ramp with New Image") run("Image to Selection...", "image=scaled_ramp opacity=100");
		else run("Image to Selection...", "image=" + tR + " opacity=100"); // can use "else" here because we have already eliminated the "No" option
		run("Flatten");
		if (originalImageDepth==8 && lut=="Grays") run("8-bit"); // restores gray if all gray settings
		rename(workingT + "+ramp");
		closeImageByTitle("scaled_ramp");
		closeImageByTitle("temp_combo");
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Ramp with Current") closeImageByTitle(tNC);
	}
		
	/* display result		 */
	restoreSettings;
	if (switchIsOn== "true") {
		hideResultsAs(tableUsed);
		restoreResultsFrom(hiddenResults);
	}
	if (activateIsOn== "true") {
		hideResultsAs(tableUsed);
	}
	setBatchMode("exit & display");
	run("Collect Garbage");
	showStatus("Line Drawing Macro Finished");
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
	function autoCalculateDecPlaces(dP){
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
	function checkForAnyResults() {
		if (nResults==0 && (getValue("results.count"))==0){
			nonImageWindowList = getList("window.titles");
			if (lengthOf(nonImageWindowList)==0) {
				Dialog.create("No Results to Work With");
				Dialog.addMessage("No obvious tables open to work with  �|_(?)_/�\nThis macro needs a table that includes the following colums in any order:\n   1.\) The paramenter to color code with\n   2.\) 4 columns containing the to and from xy pixel coordinates");
				Dialog.addRadioButtonGroup("Do you want to: ", newArray("Open New Table", "Exit"), 1, 2, "Exit"); 
				Dialog.show();
				tableDecision = Dialog.getRadioButton();
				if (tableDecision=="Exit") restoreExit("GoodBye");
				else open();
				nonImageWindowList = getList("window.titles");
			}
			nonImageWindowList = Array.concat(newArray("none - exit"), nonImageWindowList);
			Dialog.create("Select table to use...");
			Dialog.addChoice("Select Table to Activate", nonImageWindowList);
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
				nonImageWindowList = getList("window.titles");
				if (lengthOf(nonImageWindowList)==0) restoreExit("Whoops, no other tables either");
				Dialog.create("Select table to analyze...");
				Dialog.addChoice("Select Table to Activate", nonImageWindowList);
				Dialog.show();
				switchIsOn = "true";
				hideResultsAs(hiddenResults);
				tableUsed = Dialog.getChoice;
				restoreResultsFrom(tableUsed);
			}
		}
		else if ((getValue("results.count"))!=0 && nResults==0) {
			nonImageWindowList = getList("window.titles");
			if (lengthOf(list)==0) restoreExit("Whoops, no other tables either");
			Dialog.create("Select table to analyze...");
			Dialog.addChoice("Select Table to Activate", nonImageWindowList);
			Dialog.show();
			activateIsOn = "true";
			tableUsed = Dialog.getChoice;
			restoreResultsFrom(tableUsed);
		}
	}
	function checkForUnits() {  /* 
		/* v161108 (adds inches to possible reasons for checking calibration)
		*/
		getPixelSize(unit, pixelWidth, pixelHeight);
		if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="" || unit=="inches"){
			Dialog.create("No Units");
			Dialog.addCheckbox("Unit asymmetry, pixel units or dpi remnants; do you want to define units for this image?", true);
			Dialog.show();
			setScale = Dialog.getCheckbox;
			if (setScale) run("Set Scale...");
		}
	}
	function cleanLabel(string) {
		/* v161104 */
		string= replace(string, "\\^2", fromCharCode(178)); /* superscript 2 */
		string= replace(string, "\\^3", fromCharCode(179)); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, "\\^-1", fromCharCode(0x207B) + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-2", fromCharCode(0x207B) + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "\\^-^1", fromCharCode(0x207B) + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-^2", fromCharCode(0x207B) + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "(?<![A-Za-z0-9])u(?=m)", fromCharCode(181)); /* micron units */
		string= replace(string, "\\b[aA]ngstrom\\b", fromCharCode(197)); /* �ngstr�m unit symbol */
		string= replace(string, "  ", " "); /* Replace double spaces with single spaces */
		string= replace(string, "_", fromCharCode(0x2009)); /* Replace underlines with thin spaces */
		string= replace(string, "px", "pixels"); /* Expand pixel abbreviation */
		string = replace(string, " " + fromCharCode(0x00B0), fromCharCode(0x00B0)); /* Remove space before degree symbol */
		string= replace(string, " �", fromCharCode(0x2009)+"�"); /* Remove space before degree symbol */
		return string;
	}
	function closeImageByTitle(windowTitle) {  /* Cannot be used with tables */
        if (isOpen(windowTitle)) {
		selectWindow(windowTitle);
        close();
		}
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
		string = replace(string, "�", "degrees");
		string = replace(string, "0-90", "0-90�"); /* An exception to the above */
		string = replace(string, "�, degrees", "�"); /* That would be otherwise be too many degrees */
		string = replace(string, fromCharCode(0x00C2), ""); /* Remove mystery � */
		string = replace(string, " ", fromCharCode(0x2009)); /* Use this last so all spaces converted */
		return string;
	}
	function closeNonImageByTitle(windowTitle) { /* obviously */
	if (isOpen(windowTitle)) {
		selectWindow(windowTitle);
        run("Close");
		}
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
		/* ASC Color Functions */
	function getColorArrayFromColorName(colorName) {
		cA = newArray(255,255,255);
		if (colorName == "white") cA = newArray(255,255,255);
		else if (colorName == "black") cA = newArray(0,0,0);
		else if (colorName == "light_gray") cA = newArray(200,200,200);
		else if (colorName == "gray") cA = newArray(127,127,127);
		else if (colorName == "dark_gray") cA = newArray(51,51,51);
		else if (colorName == "red") cA = newArray(255,0,0);
		else if (colorName == "pink") cA = newArray(255, 192, 203);
		else if (colorName == "green") cA = newArray(0,255,0);
		else if (colorName == "blue") cA = newArray(0,0,255);
		else if (colorName == "yellow") cA = newArray(255,255,0);
		else if (colorName == "orange") cA = newArray(255, 165, 0);
		else if (colorName == "garnet") cA = newArray(120,47,64);
		else if (colorName == "gold") cA = newArray(206,184,136);
		else if (colorName == "aqua_modern") cA = newArray(75,172,198);
		else if (colorName == "blue_accent_modern") cA = newArray(79,129,189);
		else if (colorName == "blue_dark_modern") cA = newArray(31,73,125);
		else if (colorName == "blue_modern") cA = newArray(58,93,174);
		else if (colorName == "gray_modern") cA = newArray(83,86,90);
		else if (colorName == "green_dark_modern") cA = newArray(121,133,65);
		else if (colorName == "green_modern") cA = newArray(155,187,89);
		else if (colorName == "orange_modern") cA = newArray(247,150,70);
		else if (colorName == "pink_modern") cA = newArray(255,105,180);
		else if (colorName == "purple_modern") cA = newArray(128,100,162);
		else if (colorName == "red_N_modern") cA = newArray(227,24,55);
		else if (colorName == "red_modern") cA = newArray(192,80,77);
		else if (colorName == "tan_modern") cA = newArray(238,236,225);
		else if (colorName == "violet_modern") cA = newArray(76,65,132);
		else if (colorName == "yellow_modern") cA = newArray(247,238,69);
		return cA;
	}
	function setColorFromColorName(colorName) {
		colorArray = getColorArrayFromColorName(colorName);
		setColor(colorArray[0], colorArray[1], colorArray[2]);
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
		lutsCheck = 0;
		defaultLuts= getList("LUTs");
		Array.sort(defaultLuts);
		if (getDirectory("luts") == "") restoreExit("Failure to find any LUTs!");
		/* A list of frequently used LUTs for the top of the menu list . . . */
		preferredLuts = newArray("Your favorite LUTS here", "silver-asc", "viridis-linearlumin", "mpl-viridis", "mpl-plasma", "Glasbey", "Grays");
		baseLuts = newArray(lengthOf(preferredLuts));
		baseLutsCount = 0;
		for (i=0; i<lengthOf(preferredLuts); i++) {
			for (j=0; j<lengthOf(defaultLuts); j++) {
				if (preferredLuts[i]==defaultLuts[j]) {
					baseLuts[baseLutsCount] = preferredLuts[i];
					baseLutsCount += 1;
				}
			}
		}
		baseLuts=Array.trim(baseLuts, baseLutsCount);
		lutsList=Array.concat(baseLuts, defaultLuts);
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
	function removeTrailingZerosAndPeriod(string) { /* Removes any trailing zeros after a period */
		while (endsWith(string,".0")) {
			string=substring(string,0, lastIndexOf(string, ".0"));
		}
		while(endsWith(string,".")) {
			string=substring(string,0, lastIndexOf(string, "."));
		}
		return string;
	}
	function restoreExit(message){ /* Make a clean exit from a macro, restoring previous settings */
		/* 9/9/2017 added Garbage clean up suggested by Luc LaLonde - LBNL */
		restoreSettings(); /* Restore previous settings before exiting */
		setBatchMode("exit & display"); /* Probably not necessary if exiting gracefully but otherwise harmless */
		run("Collect Garbage");
		exit(message);
	}
	function restoreResultsFrom(deactivatedResults) {
		if (isOpen(deactivatedResults)) {
			selectWindow(deactivatedResults);		
			IJ.renameResults("Results");
		}
	}
	function stripExtensionsFromString(string) {
		while (lastIndexOf(string, ".")!=-1) {
			index = lastIndexOf(string, ".");
			string = substring(string, 0, index);
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
	/* v161104 This function replaces special characters with standard characters for file system compatible filenames */
	/* mod 041117 to remove spaces as well */
		string= replace(string, fromCharCode(178), "\\^2"); /* superscript 2 */
		string= replace(string, fromCharCode(179), "\\^3"); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, fromCharCode(0x207B) + fromCharCode(185), "\\^-1"); /* superscript -1 */
		string= replace(string, fromCharCode(0x207B) + fromCharCode(178), "\\^-2"); /* superscript -2 */
		string= replace(string, fromCharCode(181), "u"); /* micron units */
		string= replace(string, fromCharCode(197), "Angstrom"); /* �ngstr�m unit symbol */
		string= replace(string, fromCharCode(0x2009) + fromCharCode(0x00B0), "deg"); /* replace thin spaces degrees combination */
		string= replace(string, fromCharCode(0x2009), "_"); /* Replace thin spaces  */
		string= replace(string, " ", "_"); /* Replace spaces - these can be a problem with image combination */
		string= replace(string, "_\\+", "\\+"); /* Clean up autofilenames */
		string= replace(string, "\\+\\+", "\\+"); /* Clean up autofilenames */
		string= replace(string, "__", "_"); /* Clean up autofilenames */
		return string;
	}
	function unitLabelFromString(string, imageUnit) {
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
		else if (string=="Angle" || string=="FeretAngle" || string=="Angle_0-90" || string=="FeretAngle_0-90") unitLabel = fromCharCode(0x00B0);
		else if (string=="%Area") unitLabel = "%";
		else unitLabel = imageUnit;
	}
	return unitLabel;
	}
}
