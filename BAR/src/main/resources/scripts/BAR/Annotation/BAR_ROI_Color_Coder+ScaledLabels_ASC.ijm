/*	Fork of ROI_Color_Coder.ijm IJ BAR: https://github.com/tferr/Scripts#scripts
	http://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder
	Colorizes ROIs by matching LUT indexes to measurements in the Results table.
	Based on Tiago Ferreira, v.5.2 2015.08.13 -	v.5.3 2016.05.1 + pjl mods 6/16-30/2016 to automate defaults and add labels to ROIs
	+ add scaled labels 7/7/2016 
	+ add ability to reverse LUT and also shows min and max values for all measurements to make it easier to choose a range 8/5/2016
 	+ min and max lines for ramp
	+ added option to make a new combined image that combines the labeled image with the legend 10/1/2016
	+ added the ability to add lines on ramp for statistics
 	+ min and max lines for ramp
	+ added option to make a new combined image that combines the labeled image with the legend 10/1/2016
	+ added the ability to add lines on ramp for statistics
	+ v161117 adds more decimal place control
	+ v170914 Added garbage clean up as suggested by Luc LaLonde at LBNL.
	+ v171024 Added an option to just label the objects without color coding
	+ v171114 Added screen height sensitive menus (also tweaked for less bloat in v171117).
	+ v171117 Ramp improvements: Added minor tick labels, changed label spacing to "intervals", corrected label locations.
	+ v180104 Updated functions to latest versions.
	+ v180105 Restrict labels to within frame and fixed issue with very small font sizes.
 */
 
macro "ROI Color Coder with Scaled Labels"{
	requires("1.47r");
	saveSettings;
	close("*Ramp"); /* cleanup: closes previous ramp windows */
	// run("Remove Overlay");
	if (nImages==0){
		showMessageWithCancel("No images open or the ROI Manager is empty...\n"
        + "Run demo? (Results Table and ROI Manager will be cleared)");
	    runDemo();
	}
	/* Check to see if there is a location already set for the summary */
	if (selectionType()==0) {
		getSelectionBounds(originalSelEX, originalSelEY, originalSelEWidth, originalSelEHeight);
		selectionExists = true;
	} else selectionExists = false;
	run("Select None");
	/*
	Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* set white background */
	run("Colors...", "foreground=black background=white selection=yellow"); /* set colors */
	setOption("BlackBackground", false);
	run("Appearance...", " "); /* do not use Inverting LUT */
	if (is("Inverting LUT")==true) run("Invert LUT"); /* more effectively removes Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background)
		http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	id = getImageID();	t=getTitle(); /* get id of image and title */
	checkForUnits(); /* Required function */
	getPixelSize(unit, pixelWidth, pixelHeight);
	lcf=(pixelWidth+pixelHeight)/2; /* length conversion factor needed for morph. centroids */
	checkForRoiManager(); /* macro requires that the objects are in the ROI manager */
	checkForResults(); /* macro requires that there are results to display */
	nROIs = roiManager("count"); /* get number of ROIs to colorize */
	nRES = nResults;
	countNaN = 0; /* Set this counter here so it is not skipped by later decisions */
	menuLimit = 0.8 * screenHeight; /* used to limit menu size for small screens */
	if (nRES!=nROIs) restoreExit("Exit: Results table \(" + nRES + "\) and ROI Manager \(" + nROIs + "\) mismatch."); /* exit so that this ambiguity can be cleared up */
	if (nROIs<=1) restoreExit("Exit: ROI Manager has only \(" + nROIs + "\) entries."); /* exit so that this ambiguity can be cleared up */
	items = nROIs;
	setBatchMode(true);
	tN = stripExtensionsFromString(t); /* as in N=name could also use File.nameWithoutExtension but that is specific to last opened file */
	tN = unCleanLabel(tN); /* remove special characters and spaces that might cause issues saving file */
	imageHeight = getHeight(); imageWidth = getWidth();
	rampH = round(0.88 * imageHeight); /* suggest ramp slightly small to allow room for labels */
	fontSize = rampH/28; /* default fonts size based on imageHeight */
	originalImageDepth = bitDepth(); /* required for shadows at different bit depths */
	headings = split(String.getResultsHeadings, "\t"); /* the tab specificity avoids problems with unusual column titles */
	headingsWithRange= newArray(headings.length);
	for (i=0; i<headings.length; i++) {
		resultsColumn = newArray(items);
		for (j=0; j<items; j++)
			resultsColumn[j] = getResult(headings[i], j);
		Array.getStatistics(resultsColumn, min, max, null, null); 
		headingsWithRange[i] = headings[i] + ":  " + min + " - " + max;
	}
	if (headingsWithRange[0]==" :  Infinity - -Infinity")
		headingsWithRange[0] = "Object" + ":  1 - " + items; /* relabels ImageJ ID column */
	/* create the dialog prompt */
	Dialog.create("ROI Color Coder: " + tN);
	if (menuLimit > 752) {  /* menu bloat allowed only for small screens */
		Dialog.setInsets(6, 0, -15);
		macroP = getInfo("macro.filepath");
		/* if called from the BAR menu there will be no macro.filepath so the following checks for that */
		if (macroP=="null") Dialog.addMessage("Macro: ASC fork of BAR ROI Color Coder with Scaled Labels");
		else Dialog.addMessage("Macro: " + substring(macroP, lastIndexOf(macroP, "\\") + 1, lastIndexOf(macroP, ".ijm" )));
		Dialog.addMessage("Filename: " + tN);
		Dialog.setInsets(6, 0, 6);
	}
	Dialog.addChoice("Parameter", headingsWithRange, headingsWithRange[1]);
		luts=getLutsList(); /* I prefer this to new direct use of getList used in the recent versions of the BAR macro YMMV */
	Dialog.addChoice("LUT:", luts, luts[0]);
	Dialog.setInsets(0, 120, 12);
	Dialog.addCheckbox("Reverse LUT?", false); 
	Dialog.setInsets(-6, 0, -6);
	Dialog.addMessage("Color Coding:______Borders, Filled ROIs or None \(just labels\)?");
	Dialog.addNumber("Outlines or Solid?", 0, 0, 3, " Width in pixels \(0 to fill ROIs, -1 to label only\)");
	Dialog.addSlider("Coding opacity (%):", 0, 100, 100);
	Dialog.setInsets(18, 30, 6);
	Dialog.addCheckbox("Make copy of image with scaled labels?", true);
	Dialog.setInsets(12, 0, 6);
	Dialog.addMessage("Legend \(ramp\):______________");
	unitChoice = newArray("Auto", "Manual", unit, unit+"^2", "None", "pixels", "pixels^2", fromCharCode(0x00B0), "degrees", "radians", "%", "arb.");
	Dialog.addChoice("Unit \("+unit+"\) Label:", unitChoice, unitChoice[0]);
	Dialog.setInsets(-42, 197, -5);
	Dialog.addMessage("Auto based on\nselected parameter");
	Dialog.addString("Range:", "AutoMin-AutoMax", 11);
	Dialog.setInsets(-35, 235, 0);
	Dialog.addMessage("(e.g., 10-100)");
	Dialog.addNumber("No. of intervals:", 10, 0, 3, "Defines major ticks/label spacing");
	Dialog.addNumber("Minor tick intervals:", 0, 0, 3, "5 would add 4 ticks between labels ");
	Dialog.addChoice("Decimal places:", newArray("Auto", "Manual", "Scientific", "0", "1", "2", "3", "4"), "Auto");
	Dialog.addChoice("LUT height \(pxls\):", newArray(rampH, 128, 256, 512, 1024, 2048, 4096), rampH);
	Dialog.setInsets(-38, 195, 0);
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
	Dialog.addCheckbox("Add thin lines at true min. and max. if different", false);
	Dialog.addCheckbox("Add thin lines at true mean and " + fromCharCode(0x00B1) + " SD", false);
	Dialog.addNumber("Thin line length:", 50, 0, 3, "\(% of length tick length\)");
	Dialog.addNumber("Thin line label font:", 100, 0, 3, "% of font size");
	Dialog.addHelp("http://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder");
	Dialog.show;
		parameterWithLabel = Dialog.getChoice;
		parameter = substring(parameterWithLabel, 0, indexOf(parameterWithLabel, ":  "));
		lut = Dialog.getChoice;
		revLut = Dialog.getCheckbox;
		stroke = Dialog.getNumber;
		alpha = pad(toHex(255*Dialog.getNumber/100));
		addLabels = Dialog.getCheckbox();
		unitLabel = Dialog.getChoice();
		rangeS = Dialog.getString; /* changed from original to allow negative values - see below */
		numLabels = Dialog.getNumber + 1; /* The number of major ticks/labels is one more than the intervals */
		minorTicks = Dialog.getNumber; /* The number of major ticks/labels is one more than the intervals */
		dpChoice = Dialog.getChoice;
		rampChoice = parseFloat(Dialog.getChoice);
		fontStyle = Dialog.getChoice;
			if (fontStyle=="unstyled") fontStyle="";
		fontName = Dialog.getChoice;
		fontSize = Dialog.getNumber;
		ticks = Dialog.getCheckbox;
		rotLegend = Dialog.getCheckbox;
		minmaxLines = Dialog.getCheckbox;
		statsRampLines = Dialog.getCheckbox;
		statsRampTicks = Dialog.getNumber;
		thinLinesFontSTweak = Dialog.getNumber;
	if (rotLegend && rampChoice==rampH) rampH = imageHeight - 2 * fontSize; /* tweaks automatic height selection for vertical legend */
	else rampH = rampChoice;
	range = split(rangeS, "-");
	if (range.length==1) {
		min= NaN; max= parseFloat(range[0]);
	} else {
		min= parseFloat(range[0]); max= parseFloat(range[1]);
	}
	if (indexOf(rangeS, "-")==0) min = 0 - min; /* checks to see if min is a negative value (lets hope the max isn't). */
	fontSR2 = fontSize * thinLinesFontSTweak/100;
	rampLW = maxOf(1, round(rampH/512)); /* ramp line width with a minimum of 1 pixel */
	minmaxLW = round(rampLW / 4); /* line widths for ramp stats */
	/* get values for chosen parameter */
	values= newArray(items);
	if (parameter=="Object") for (i=0; i<items; i++) values[i]= i+1;
	else for (i=0; i<items; i++) values[i]= getResult(parameter,i);
	Array.getStatistics(values, arrayMin, arrayMax, arrayMean, arraySD); 
	if (isNaN(min)) min= arrayMin;
	if (isNaN(max)) max= arrayMax;
	coeffVar = arraySD*100/arrayMean;
	sortedValues = Array.copy(values); sortedValues = Array.sort(sortedValues); /* all this effort to get the median without sorting the original array! */
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
	parameterLabel = stripUnitFromString(parameter);
	unitLabel= cleanLabel(unitLabel);
	/* Begin object color coding if stroke set */
	if (stroke>=0) {
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
		roiColors= loadLutColors(lut); /* load the LUT as a hexColor array: requires function */
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
					setLineWidth(rampLW); /* reset line width */
				}
			}
		}
		/* end draw minor ticks */
		/* now add lines and the true min and max and for stats if chosen in previous dialog */
		if (minmaxLines || statsRampLines) {
			newImage("label_mask", "8-bit black", getWidth(), getHeight(), 1);
			setColor("white");
			setLineWidth(rampLW);
			if (minmaxLines) {
				if (min==max) restoreExit("Something terribly wrong with this range!");
				trueMaxFactor = (arrayMax-min)/(max-min);
				maxPos = round(fontSize/2 + (rampH * (1 - trueMaxFactor)) +1.5*fontSize)-1;
				trueMinFactor = (arrayMin-min)/(max-min);
				minPos = round(fontSize/2 + (rampH * (1 - trueMinFactor)) +1.5*fontSize)-1;
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
				meanPos = round(fontSize/2 + (rampH * (1 - meanFactor)) +1.5*fontSize)-1;
				plusSDPos = round(fontSize/2 + (rampH * (1 - plusSDFactor)) +1.5*fontSize)-1;
				minusSDPos = round(fontSize/2 + (rampH * (1 - minusSDFactor)) +1.5*fontSize)-1;
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
			/* now use a mask to create black outline around white text to stand out against ramp colors */
			rampOutlineStroke = maxOf(1,round(rampLW/2));
			setThreshold(0, 128);
			setOption("BlackBackground", false);
			run("Convert to Mask");
			selectWindow(tR);
			run("Select None");
			getSelectionFromMask("label_mask");
			run("Enlarge...", "enlarge=[rampOutlineStroke] pixel");
			setBackgroundColor(0, 0, 0);
			run("Clear");
			run("Select None");
			getSelectionFromMask("label_mask");
			setBackgroundColor(255, 255, 255);
			run("Clear");
			run("Select None");
			closeImageByTitle("label_mask");
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
			rampParameterLabel += ", " + rampUnitLabel;
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
		for (countNaN=0, i=0; i<items; i++) {
			showStatus("Coloring object " + i + ", " + (nROIs-i) + " more to go");
			if (isNaN(values[i])) countNaN++;
			if (!revLut) {
				if (values[i]<=min) lutIndex= 0;
				else if (values[i]>max) lutIndex= 255;
				else lutIndex= round(255 * (values[i] - min) / (max - min));
			}
			else {
				if (values[i]<=min) lutIndex= 255;
				else if (values[i]>max) lutIndex= 0;
				else lutIndex= round(255 * (max - values[i]) / (max - min));
			}
			roiManager("select", i);
			if (stroke>0) {
				roiManager("Set Line Width", stroke);
				roiManager("Set Color", alpha+roiColors[lutIndex]);
			} else
				roiManager("Set Fill Color", alpha+roiColors[lutIndex]);
			labelValue = values[i];
			labelString = d2s(labelValue,decPlaces); /* Reduce Decimal places for labeling - move these two lines to below the labels you prefer */
			labelString = removeTrailingZerosAndPeriod(labelString); /* remove trailing characters */
			// roiManager("Rename", labelString); /* label roi with feature value: not necessary if creating new labels */
			Overlay.show;		
		}
		// roiManager("Show All without labels");
	}
	/* End of object coloring */
	if (!addLabels) {
		roiManager("show all with labels");
		run("Flatten"); /* creates an RGB copy of the image with color coded objects or not */
	}
	else {
		roiManager("Show All without labels");
		/* Now to add scaled object labels */
		/* First: set default label settings */
		outlineStrokePC = 6; /* default outline stroke: % of font size */
		shadowDropPC = 10;  /* default outer shadow drop: % of font size */
		dIShOPC = 5; /* default inner shadow drop: % of font size */
		offsetX = maxOf(1, round(imageWidth/150)); /* default offset of label from edge */
		offsetY = maxOf(1, round(imageHeight/150)); /* default offset of label from edge */
		fontColor = "white";
		outlineColor = "black"; 	
		paraLabFontSize = round((imageHeight+imageWidth)/45);
		statsLabFontSize = round((imageHeight+imageWidth)/60);
		/* Feature Label Formatting Options Dialog . . . */
		Dialog.create("Feature Label Formatting Options");
			if (lut!="Grays")
				colorChoice = newArray("white", "black", "light_gray", "gray", "dark_gray", "aqua_modern", "blue_modern", "garnet", "gold", "green_modern", "orange_modern", "pink_modern", "red_modern", "violet_modern", "yellow_modern"); 
			else colorChoice = newArray("white", "black", "light_gray", "gray", "dark_gray");
			Dialog.addChoice("Object label color:", colorChoice, colorChoice[0]);
			Dialog.addNumber("Font scaling:", 60,0,3,"% of Auto");
			Dialog.addNumber("Restrict label font size:", round(imageWidth/90),0,4, "Min to ");
			Dialog.setInsets(-28, 90, 0);
			Dialog.addNumber("Max", round(imageWidth/16), 0, 4, "Max");
			fontStyleChoice = newArray("bold", "bold antialiased", "italic", "bold italic", "unstyled");
			Dialog.addChoice("Font style:", fontStyleChoice, fontStyleChoice[1]);
			fontNameChoice = newArray("SansSerif", "Serif", "Monospaced");
			Dialog.addChoice("Font name:", fontNameChoice, fontNameChoice[0]);
			Dialog.addChoice("Decimal places:", newArray("Auto", "Manual", "Scientific", "0", "1", "2"), dpChoice); /* reuse previous dpChoice as default */
			Dialog.addNumber("Outline stroke:", outlineStrokePC,0,3,"% of font size");
			Dialog.addChoice("Outline (background) color:", colorChoice, colorChoice[1]);
			Dialog.addNumber("Shadow drop: ±", shadowDropPC,0,3,"% of font size");
			Dialog.addNumber("Shadow displacement Right: ±", shadowDropPC,0,3,"% of font size");
			Dialog.addNumber("Shadow Gaussian blur:", floor(0.75 * shadowDropPC),0,3,"% of font size");
			Dialog.addNumber("Shadow darkness \(darkest = 100%\):", 50,0,3,"%, neg.= glow");
			Dialog.addNumber("Inner shadow drop: ±", dIShOPC,0,3,"% of font size");
			Dialog.addNumber("Inner displacement right: ±", dIShOPC,0,3,"% of font size");
			Dialog.addNumber("Inner shadow mean blur:",floor(dIShOPC/2),1,2,"pixels");
			Dialog.addNumber("Inner shadow darkness \(darkest = 100%\):", 20,0,3,"%");
			Dialog.setInsets(3, 0, 3);
			if (isNaN(getResult("mc_X\(px\)",0))) {
				Dialog.addChoice("Object labels at: ", newArray("ROI Center", "Morphological Center"), "ROI Center");
				Dialog.setInsets(-3, 40, 6);
				Dialog.addMessage("If selected, morphological centers will be added to the results table.");
			}
			else Dialog.addChoice("Object Label At:", newArray("ROI Center", "Morphological Center"), "Morphological Center");
			paraLocChoice = newArray("None", "Top Left", "Top Right", "Center", "Bottom Left", "Bottom Right", "Center of New Selection"); 
			Dialog.addChoice("Location of Parameter Label \(\"None\" = No Parameter Title\):", paraLocChoice, paraLocChoice[1]);
			Dialog.addNumber("Parameter label font size:", paraLabFontSize);			Dialog.show();
			fontColor = Dialog.getChoice(); /* Object label color */
			fontSCorrection =  Dialog.getNumber()/100;
			minLFontS = Dialog.getNumber();
			maxLFontS = Dialog.getNumber(); 
			fontStyle = Dialog.getChoice();
			fontName = Dialog.getChoice();
			dpChoice = Dialog.getChoice();
			outlineStrokePC = Dialog.getNumber();
			outlineColor = Dialog.getChoice();
			shadowDrop = Dialog.getNumber();
			shadowDisp = Dialog.getNumber();
			shadowBlur = Dialog.getNumber();
			shadowDarkness = Dialog.getNumber();
			innerShadowDrop = Dialog.getNumber();
			innerShadowDisp = Dialog.getNumber();
			innerShadowBlur = Dialog.getNumber();
			innerShadowDarkness = Dialog.getNumber();
			ctrChoice = Dialog.getChoice(); /* Choose ROI or morphological centers for object labels */
			paraLabPos = Dialog.getChoice(); /* Parameter Label Position */
			paraLabFontSize = Dialog.getNumber();
			if (isNaN(getResult("mc_X\(px\)",0)) && ctrChoice=="Morphological Center") 
				AddMCsToResultsTable ();
		selectWindow(t);
		paraLabChoice = true;
		if (paraLabPos=="None") paraLabChoice = false;
		else if (paraLabPos=="Center of New Selection"){
			batchMode = is("Batch Mode"); /* Store batch status mode before toggling */
			if (batchMode) setBatchMode("exit & display"); /* Toggle batch mode off */
			setTool("rectangle");
			msgtitle="Location for the summary labels...";
			msg = "Draw a box in the image where you want to center the summary labels...";
			waitForUser(msgtitle, msg);
			getSelectionBounds(newSelEX, newSelEY, newSelEWidth, newSelEHeight);
			run("Select None");
			if (batchMode) setBatchMode(true); /* Toggle batch mode back on if previously on */
		}
		shadowDarkness = (255/100) * (abs(shadowDarkness));
		innerShadowDarkness = (255/100) * (100 - (abs(innerShadowDarkness)));
		if (dpChoice=="Auto")
			decPlaces = autoCalculateDecPlaces(decPlaces);
		else if (dpChoice=="Manual") 
			decPlaces = getNumber("Choose Number of Decimal Places", 0);
		else if (dpChoice=="Scientific")
			decPlaces = -1;
		else decPlaces = dpChoice;
		if (parameter=="Object") decPlaces = 0; /* This should be an integer */
		if (fontStyle=="unstyled") fontStyle="";
		if (stroke>=0) {
			run("Flatten"); /* Flatten converts to RGB so . . .  */
			rename(tN + "_" + parameterLabel + "_labels");
			if (originalImageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
		} else {
			run("Duplicate...", "title=labeled");
			rename(tN + "_" + parameterLabel + "_labels");
		}
		flatImage = getTitle();
		if (is("Batch Mode")==false) setBatchMode(true);
		newImage("label_mask", "8-bit black", imageWidth, imageHeight, 1);
		// roiManager("show none");
		/*
		iterate through the ROI Manager list and draw scaled labels onto mask */
		fontArray = newArray(items);
		for (i=0; i<items; i++) {
			showStatus("Creating labels for object " + i + ", " + (roiManager("count")-i) + " more to go");
			roiManager("Select", i);
			labelValue = values[i];
			if (dpChoice=="Auto")
				decPlaces = autoCalculateDecPlaces(labelValue);
			labelString = d2s(labelValue,decPlaces); /* Reduce Decimal places for labeling - move these two lines to below the labels you prefer */
			Roi.getBounds(roiX, roiY, roiWidth, roiHeight);
			if (roiWidth>=roiHeight) roiMin = roiHeight;
			else roiMin = roiWidth;
			lFontS = fontSize; /* initial estimate */
			setFont(fontName,lFontS,fontStyle);
			lFontS = fontSCorrection * fontSize * roiMin/(getStringWidth(labelString));
			if (lFontS>maxLFontS) lFontS = maxLFontS; 
			if (lFontS<minLFontS) lFontS = minLFontS;
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
			setColorFromColorName("white");
			drawString(labelString, textOffset, textDrop);
			fontArray[i] = lFontS;
		}
		roiManager("show none");
		setThreshold(0, 128);
		setOption("BlackBackground", false);
		run("Convert to Mask");
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
		outlineStroke = round(fontFactor * outlineStrokePC);
		if (outlineStrokePC>0) outlineStroke = maxOf(1,outlineStroke); /* set a minimum stroke */
		labelShadowDrop = floor(fontFactor * labelShadowDrop);
		if (shadowDrop>0) labelShadowDrop = maxOf(1+outlineStroke, labelShadowDrop);
		labelShadowDisp = floor(fontFactor * labelShadowDisp);
		if (shadowDisp>0) labelShadowDisp = maxOf(1+outlineStroke, labelShadowDisp);
		labelShadowBlur = floor(fontFactor * labelShadowBlur);
		if (shadowBlur>0) labelShadowBlur = maxOf(outlineStroke, labelShadowBlur);
		labelInnerShadowDrop = floor(minFontFactor * labelInnerShadowDrop);
		labelInnerShadowDisp = floor(minFontFactor * labelInnerShadowDisp);
		labelInnerShadowBlur = floor(minFontFactor * labelInnerShadowBlur);
		/*
		Create drop labelShadow if desired */
		if (labelShadowDrop!=0 || labelShadowDisp!=0)
			createShadowDropFromMask5(labelShadowDrop, labelShadowDisp, labelShadowBlur, shadowDarkness, outlineStroke);
		/*	Create inner shadow if desired */
		if (labelInnerShadowDrop!=0 || labelInnerShadowDisp!=0) 
			createInnerShadowFromMask4(labelInnerShadowDrop, labelInnerShadowDisp, labelInnerShadowBlur, innerShadowDarkness);
		run("Select None");
		/* Create outer shadow or glow */
		if (isOpen("shadow") && shadowDarkness>0) imageCalculator("Subtract",flatImage,"shadow");
		if (isOpen("shadow") && shadowDarkness<0) imageCalculator("Add", flatImage,"shadow");	/* Glow */
		selectWindow(flatImage);
		/* Create outline around text */
		getSelectionFromMask("label_mask");
		run("Enlarge...", "enlarge=[outlineStroke] pixel");
		setBackgroundFromColorName(outlineColor);
		run("Clear");
		run("Select None");
		/* Create text */
		getSelectionFromMask("label_mask");
		setBackgroundFromColorName(fontColor);
		run("Clear");
		run("Select None");
		/* Create inner shadow if requested */
		if (isOpen("inner_shadow") && innerShadowDarkness>0)
			imageCalculator("Subtract",flatImage,"inner_shadow");
		if (isOpen("inner_shadow") && innerShadowDarkness<0)		/* Glow */
			imageCalculator("Add", flatImage,"inner_shadow");
		if (originalImageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
		closeImageByTitle("shadow");
		closeImageByTitle("inner_shadow");
		closeImageByTitle("label_mask");
		if (stroke>=0) flatImage = getTitle();
	/*	Now repeat with the Parameter Label over the top of the object labels */
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
		outlineStroke = round(fontFactor * outlineStrokePC);
		labelShadowDrop = floor(fontFactor * labelShadowDrop);
		labelShadowDisp = floor(fontFactor * labelShadowDisp);
		labelShadowBlur = floor(fontFactor * labelShadowBlur);
		labelInnerShadowDrop = floor(fontFactor * labelInnerShadowDrop);
		labelInnerShadowDisp = floor(fontFactor * labelInnerShadowDisp);
		labelInnerShadowBlur = floor(fontFactor * labelInnerShadowBlur);
		newImage("label_mask", "8-bit black", imageWidth, imageHeight, 1);
		if (paraLabPos!="None") {				/* recombine units and labels that were used in Ramp */
		if (unitLabel!="") label = parameterLabel + ", " + unitLabel;
		else label = parameterLabel;
		if (paraLabChoice) {
			setFont(fontName,paraLabFontSize, fontStyle);
			sW = getStringWidth(label);
		}
		if (paraLabPos == "Top Left") {
			selEX = offsetX;
			selEY = offsetY;
		} else if (paraLabPos == "Top Right") {
			selEX = imageWidth - sW - offsetX;
			selEY = offsetY;
		} else if (paraLabPos == "Center") {
			selEX = round((imageWidth - sW)/2);
			selEY = round((imageHeight - fontSize)/2);
		} else if (paraLabPos == "Bottom Left") {
			selEX = offsetX;
			selEY = imageHeight - offsetY - fontSize; 
		} else if (paraLabPos == "Bottom Right") {
			selEX = imageWidth - sW - offsetX;
			selEY = imageHeight - offsetY - fontSize;
		} else if (paraLabPos == "Center of New Selection"){
			/* Area selection previously obtained before mask routine so as not selecting on black image */
			selEX = round(newSelEX + ((newSelEWidth - sW)/2));
			selEY = round(newSelEY + ((newSelEHeight + fontSize)/2));
		} if (selEY<=1.5*paraLabFontSize) selEY += paraLabFontSize;
		if (selEX<offsetX) selEX = offsetX;
		endX = selEX + sW;
		if ((endX+offsetX)>imageWidth) selEX = imageWidth - sW - offsetX;
		labelX = selEX;
		labelY = selEY;
		setColorFromColorName("white");
		drawString(label, labelX, labelY);
		setThreshold(0, 128);
		setOption("BlackBackground", false);
		run("Convert to Mask");
		/*
		Create parameter label drop shadow - no option dialog */
			if (labelShadowDrop!=0 || labelShadowDisp!=0)
				createShadowDropFromMask5(labelShadowDrop, labelShadowDisp, labelShadowBlur, shadowDarkness, outlineStroke);
			/*	Create inner shadow if desired */
			if (labelInnerShadowDrop!=0 || labelInnerShadowDisp!=0 || labelInnerShadowBlur!=0) 
				createInnerShadowFromMask4(labelInnerShadowDrop, labelInnerShadowDisp, labelInnerShadowBlur, innerShadowDarkness);
			/* Apply drop shadow or glow */
			if (isOpen("shadow") && shadowDarkness>0)
				imageCalculator("Subtract", flatImage,"shadow");
			if (isOpen("shadow") && shadowDarkness<0)	/* Glow */
				imageCalculator("Add", flatImage,"shadow");
			run("Select None");
			/* Create outline around text */
			getSelectionFromMask("label_mask");
			run("Enlarge...", "enlarge=[outlineStroke] pixel");
			setBackgroundFromColorName(outlineColor);
			run("Clear");
			run("Select None");
			/* Create text */
			getSelectionFromMask("label_mask");
			setBackgroundFromColorName(fontColor);
			run("Clear");
			run("Select None");
			/* Create inner shadow or glow if requested */
			if (isOpen("inner_shadow") && innerShadowDarkness>0)
				imageCalculator("Subtract", flatImage,"inner_shadow");
			if (isOpen("inner_shadow") && innerShadowDarkness<0)	/* Glow */
				imageCalculator("Add", flatImage,"inner_shadow");
			selectWindow(flatImage);
			rename(tN + "_" + parameterLabel + "\+objectlabels");
			flatImage = getTitle();
			closeImageByTitle("shadow");
			closeImageByTitle("inner_shadow");
			closeImageByTitle("label_mask");
		}
		selectWindow(flatImage);
	}
	/*		End of optional parameter label section
	*/
	if (stroke>=0) {
		run("Colors...", "foreground=black background=white selection=yellow"); /* reset colors */
		selectWindow(flatImage);
		if (countNaN!=0)
			print("\n>>>> ROI Color Coder:\n"
				+ "Some values from the \""+ parameter +"\" column could not be retrieved.\n"
				+ countNaN +" ROI(s) were labeled with a default color.");
		rename(getTitle() + "\+coded");
		tNC = getTitle();
		/* Image and Ramp combination dialog */
		Dialog.create("Combine Labeled Image and Legend?");
			if (canvasH>imageHeight) comboChoice = newArray("No", "Combine Scaled Ramp with Current", "Combine Scaled Ramp with New Image");
			else if (canvasH>(0.93 * imageHeight)) comboChoice = newArray("No", "Combine Ramp with Current", "Combine Ramp with New Image"); /* 93% is close enough */
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
			srW = getWidth + maxOf(2,imageWidth/500);
			comboW = srW + imageWidth + maxOf(2,imageWidth/500);
			selectWindow(tNC);
			if (createCombo=="Combine Scaled Ramp with New Image" || createCombo=="Combine Ramp with New Image") run("Duplicate...", "title=temp_combo");
			run("Canvas Size...", "width="+comboW+" height="+imageHeight+" position=Top-Left");
			makeRectangle(imageWidth + maxOf(2,imageWidth/500), round((imageHeight-canvasH)/2), srW, imageHeight);
			if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Scaled Ramp with New Image") run("Image to Selection...", "image=scaled_ramp opacity=100");
			else run("Image to Selection...", "image=" + tR + " opacity=100"); /* can use "else" here because we have already eliminated the "No" option */
			run("Flatten");
			if (originalImageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
			rename(tNC + "+ramp");
			closeImageByTitle("scaled_ramp");
			closeImageByTitle("temp_combo");
			if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Ramp with Current") closeImageByTitle(tNC);
		}
	}
	else rename(t + "_" + parameterLabel + "_labels");
	setBatchMode("exit & display");
	restoreSettings;
	showStatus("ROI Color Coder with Scaled Labels Macro Finished");
	beep(); wait(300); beep(); wait(300); beep();
	run("Collect Garbage");
	/*
		   ( 8(|)	( 8(|)	Functions	@@@@@:-)	@@@@@:-)
   */
	function AddMCsToResultsTable () {
/* 	Based on "MCentroids.txt" Morphological centroids by thinning assumes white particles: G.Landini
	http://imagejdocu.tudor.lu/doku.php?id=plugin:morphology:morphological_operators_for_imagej:start
	http://www.mecourse.com/landinig/software/software.html
	Modified to add coordinates to Results Table: Peter J. Lee NHMFL  7/20-29/2016
	v180102 updated
	v180104 removed unnecessary changes to settings
*/
	workingTitle = getTitle();
	if (!checkForPlugin("morphology_collection")) restoreExit("Exiting: Gabriel Landini's morphology suite is needed to run this macro.");
	binaryCheck(workingTitle); /* Makes sure image is binary and sets to white background, black objects */
	checkForRoiManager(); /* This macro uses ROIs and a Results table that matches in count */
	roiOriginalCount = roiManager("count");
	batchMode = is("Batch Mode"); /* Store batch status mode before toggling */
	if (!batchMode) setBatchMode(true); /* Toggle batch mode on if previously off */
	start = getTime();
	getPixelSize(selectedUnit, pixelWidth, pixelHeight);
	lcf=(pixelWidth+pixelHeight)/2;
	objects = roiManager("count");
	mcImageWidth = getWidth();
	mcImageHeight = getHeight();
	showStatus("Looping through all " + roiOriginalCount + " objects for morphological centers . . .");
	for (i=0 ; i<roiOriginalCount; i++) {
		showProgress(-i, roiManager("count"));
		selectWindow(workingTitle);
		roiManager("select", i);
		Roi.getBounds(Rx, Ry, Rwidth, Rheight);
		setResult("ROIctr_X\(px\)", i, round(Rx + Rwidth/2));
		setResult("ROIctr_Y\(px\)", i, round(Ry + Rheight/2));
		Roi.getContainedPoints(RPx, RPy); /* this includes holes when ROIs are used so no hole filling is needed */
		newImage("Contained Points "+i,"8-bit black",Rwidth,Rheight,1); /* give each sub-image a unique name for debugging purposes */
		for (j=0; j<RPx.length; j++)
			setPixel(RPx[j]-Rx, RPy[j]-Ry, 255);
		selectWindow("Contained Points "+i);
		run("BinaryThin2 ", "kernel_a='0 2 2 0 1 1 0 0 2 ' kernel_b='0 0 2 0 1 1 0 2 2 ' rotations='rotate 45' iterations=-1 white");
		for (RPx=1; RPx<(Rwidth-1); RPx++){
			for (RPy=1; RPy<(Rheight-1); RPy++){ /* start at "1" because there should not be a pixel at the border */
				if((getPixel(RPx, RPy))==255) {  
					setResult("mc_X\(px\)", i, RPx+Rx);
					setResult("mc_Y\(px\)", i, RPy+Ry);
					setResult("mc_offsetX\(px\)", i, getResult("X",i)-(RPx+Rx));
					setResult("mc_offsetY\(px\)", i, getResult("Y",i)-(RPy+Ry));
					// if (lcf!=1) {
						// setResult("mc_X\(" + selectedUnit + "\)", i, (RPx+Rx)*lcf); /* perhaps not too useful */
						// setResult("mc_Y\(" + selectedUnit + "\)", i, (RPy+Ry)*lcf); /* perhaps not too useful */
					// }
					RPy = Rheight;
					RPx = Rwidth; /* one point and done */
				}
			}
		}
		closeImageByTitle("Contained Points "+i);
	}
	updateResults();
	run("Select None");
	if (!batchMode) setBatchMode(false); /* Toggle batch mode off */
	showStatus("MC Function Finished: " + roiManager("count") + " objects analyzed in " + (getTime()-start)/1000 + "s.");
	beep(); wait(300); beep(); wait(300); beep();
	run("Collect Garbage"); 
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
	function binaryCheck(windowTitle) { /* for black objects on white background */
		/* v180104 added line to remove inverting LUT and changed to auto default threshold */
		selectWindow(windowTitle);
		if (is("binary")==0) run("8-bit");
		/* Quick-n-dirty threshold if not previously thresholded */
		getThreshold(t1,t2); 
		if (t1==-1)  {
			run("8-bit");
			run("Auto Threshold", "method=Default");
			run("Convert to Mask");
			}
		/* Make sure black objects on white background for consistency */
		if (((getPixel(0, 0))==0 || (getPixel(0, 1))==0 || (getPixel(1, 0))==0 || (getPixel(1, 1))==0))
			run("Invert"); 
		/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
			i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
		if (((getPixel(0, 0))+(getPixel(0, 1))+(getPixel(1, 0))+(getPixel(1, 1))) != 4*(getPixel(0, 0)) ) 
				restoreExit("Border Issue"); 	
		if (is("Inverting LUT")==true) run("Invert LUT");
	}
	function checkForPlugin(pluginName) {
		/* v161102 changed to true-false */
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
			subFolderList = newArray(pluginList.length);
			for (i=0; i<pluginList.length; i++) {
				if (endsWith(pluginList[i], "/")) {
					subFolderList[subFolderCount] = pluginList[i];
					subFolderCount = subFolderCount +1;
				}
			}
			subFolderList = Array.slice(subFolderList, 0, subFolderCount);
			for (i=0; i<subFolderList.length; i++) {
				if (File.exists(pluginDir + subFolderList[i] +  "\\" + pluginName)) {
					pluginCheck = true;
					showStatus(pluginName + " found in: " + pluginDir + subFolderList[i]);
					i = subFolderList.length;
				}
			}
		}
		return pluginCheck;
	}
	function checkForResults() {
		nROIs = roiManager("count");
		nRES = nResults;
		if (nRES==0)	{
			Dialog.create("No Results to Work With");
			Dialog.addCheckbox("Run Analyze-particles to generate table?", true);
			Dialog.addMessage("This macro requires a Results table to analyze.\n \nThere are   " + nRES +"   results.\nThere are    " + nROIs +"   ROIs.");
			Dialog.show();
			analyzeNow = Dialog.getCheckbox(); /* if (analyzeNow==true) ImageJ analyze particles will be performed, otherwise exit; */
			if (analyzeNow==true) {
				if (roiManager("count")!=0) {
					roiManager("deselect")
					roiManager("delete"); 
				}
				setOption("BlackBackground", false);
				run("Analyze Particles..."); /* let user select settings */
			}
			else restoreExit("Goodbye, your previous setting will be restored.");
		}
	}
	function checkForRoiManager() {
		/* v161109 adds the return of the updated ROI count and also adds dialog if there are already entries just in case . .
			v180104 only asks about ROIs if there is a mismatch with the results */
		nROIs = roiManager("count");
		nRES = nResults; /* Used to check for ROIs:Results mismatch */
		if(nROIs==0) runAnalyze = true; /* Assumes that ROIs are required and that is why this function is being called */
		else if(nROIs!=nRES) runAnalyze = getBoolean("There are " + nRES + " results and " + nROIs + " ROIs; do you want to clear the ROI manager and reanalyze?");
		else runAnalyze = false;
		if (runAnalyze) {
			roiManager("reset");
			Dialog.create("Analysis check");
			Dialog.addCheckbox("Run Analyze-particles to generate new roiManager values?", true);
			Dialog.addMessage("This macro requires that all objects have been loaded into the roi manager.\n \nThere are   " + nRES +"   results.\nThere are   " + nROIs +"   ROIs.");
			Dialog.show();
			analyzeNow = Dialog.getCheckbox();
			if (analyzeNow) {
				setOption("BlackBackground", false);
				if (nResults==0)
					run("Analyze Particles...", "display add");
				else run("Analyze Particles..."); /* let user select settings */
				if (nResults!=roiManager("count"))
					restoreExit("Results and ROI Manager counts do not match!");
			}
			else restoreExit("Goodbye, your previous setting will be restored.");
		}
		return roiManager("count"); /* returns the new count of entries */
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
		/* v161104 */
		string= replace(string, "\\^2", fromCharCode(178)); /* superscript 2 */
		string= replace(string, "\\^3", fromCharCode(179)); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, "\\^-1", fromCharCode(0x207B) + fromCharCode(185)); /* superscript -1 */
		string= replace(string, "\\^-2", fromCharCode(0x207B) + fromCharCode(178)); /* superscript -2 */
		string= replace(string, "\\^-^1", fromCharCode(0x207B) + fromCharCode(185)); /*	superscript -1 */
		string= replace(string, "\\^-^2", fromCharCode(0x207B) + fromCharCode(178)); /*	superscript -2 */
		string= replace(string, "(?<![A-Za-z0-9])u(?=m)", fromCharCode(181)); /* micrometer units*/
		string= replace(string, "\\b[aA]ngstrom\\b", fromCharCode(197)); /* angstrom symbol*/
		string= replace(string, "  ", " "); /* double spaces*/
		string= replace(string, "_", fromCharCode(0x2009)); /* replace underlines with thin spaces*/
		string= replace(string, "px", "pixels"); /* expand pixel abbreviate*/
		string = replace(string, " " + fromCharCode(0x00B0), fromCharCode(0x00B0)); /*	remove space before degree symbol */
		string= replace(string, " °", fromCharCode(0x2009)+"°"); /*	remove space before degree symbol */
		return string;
	}
	function closeImageByTitle(windowTitle) {  /* cannot be used with tables */
        if (isOpen(windowTitle)) {
		selectWindow(windowTitle);
        close();
		}
	}
	function createInnerShadowFromMask4(iShadowDrop, iShadowDisp, iShadowBlur, iShadowDarkness) {
		/* requires previous run of:  originalImageDepth = bitDepth();
		because this version works with different bitDepths
		v161115 calls four variables: drop, displacement blur and darkness */
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
		run("Invert");  /* create an image that can be subtracted - works better for color than min */
		divider = (100 / abs(iShadowDarkness));
		run("Divide...", "value=[divider]");
	}
	function createShadowDropFromMask5(oShadowDrop, oShadowDisp, oShadowBlur, oShadowDarkness, oStroke) {
		/* requires previous run of:  originalImageDepth = bitDepth();
		because this version works with different bitDepths
		v161115 calls five variables: drop, displacement blur and darkness */
		showStatus("Creating drop shadow for labels . . . ");
		newImage("shadow", "8-bit black", imageWidth, imageHeight, 1);
		getSelectionFromMask("label_mask");
		getSelectionBounds(selMaskX, selMaskY, selMaskWidth, selMaskHeight);
		setSelectionLocation(selMaskX + oShadowDisp, selMaskY + oShadowDrop);
		setBackgroundColor(255,255,255);
		if (oStroke>0) run("Enlarge...", "enlarge=[oStroke] pixel"); /* adjust so shadow extends beyond stroke thickness */
		run("Clear");
		run("Select None");
		if (oShadowBlur>0) {
			run("Gaussian Blur...", "sigma=[oShadowBlur]");
			// run("Unsharp Mask...", "radius=[oShadowBlur] mask=0.4"); /* Make Gaussian shadow edge a little less fuzzy */
		}
		/* Now make sure shadow of glow does not impact outline */
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
	function expandLabel(string) {  /* mostly for better looking summary tables */
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
		string = replace(string, "0-90", "0-90°"); /* put this here as an exception to the above */
		string = replace(string, "°, degrees", "°"); /* that would be otherwise too many degrees */
		string = replace(string, fromCharCode(0x00C2), ""); /* remove mystery Â */
		string = replace(string, " ", fromCharCode(0x2009)); /* use this last so all spaces converted */
		return string;
	}
/*
	 Macro Color Functions
 */
	function getColorArrayFromColorName(colorName) {
		cA = newArray(255,255,255);
		if (colorName == "white") cA = newArray(255,255,255);
		else if (colorName == "black") cA = newArray(0,0,0);
		else if (colorName == "light_gray") cA = newArray(200,200,200);
		else if (colorName == "gray") cA = newArray(127,127,127);
		else if (colorName == "dark_gray") cA = newArray(51,51,51);
		else if (colorName == "red") cA = newArray(255,0,0);
		else if (colorName == "pink") cA = newArray(255, 192, 203);
		else if (colorName == "green") cA = newArray(255,255,0);
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
		lutsCheck = 0;
		defaultLuts= getList("LUTs");
		Array.sort(defaultLuts);
		if (getDirectory("luts") == "") restoreExit("Failure to find any LUTs!");
		/* A list of frequently used luts for the top of the list . . . */
		preferredLuts = newArray("Your favorite LUTS here", "silver-asc", "viridis-linearlumin", "mpl-viridis", "mpl-plasma", "Glasbey", "Grays");
		baseLuts = newArray(preferredLuts.length);
		baseLutsCount = 0;
		for (i=0; i<preferredLuts.length; i++) {
			for (j=0; j<defaultLuts.length; j++) {
				if (preferredLuts[i]==defaultLuts[j]) {
					baseLuts[baseLutsCount] = preferredLuts[i];
					baseLutsCount += 1;
				}
			}
		}
		baseLuts=Array.trim(baseLuts, baseLutsCount);
		lutsList=Array.concat(baseLuts, defaultLuts);
		return lutsList; /* required to return new array */
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
		run("Create Selection"); /* selection inverted perhaps because mask has inverted lut? */
		run("Make Inverse");
		selectWindow(tempTitle);
		run("Restore Selection");
		if (!batchMode) setBatchMode(false); /* return to original batch mode */
	}
	function removeTrailingZerosAndPeriod(string) { /* removes trailing zeros after period */
		while (endsWith(string,".0")) {
			string=substring(string,0, lastIndexOf(string, ".0"));
		}
		while(endsWith(string,".")) {
			string=substring(string,0, lastIndexOf(string, "."));
		}
		return string;
	}
	function restoreExit(message){ /* clean up before aborting macro then exit */
		/* 9/9/2017 added Garbage clean up suggested by Luc LaLonde - LBNL */
		restoreSettings(); /* clean up before exiting */
		setBatchMode("exit & display"); /* not sure if this does anything useful if exiting gracefully but otherwise harmless */
		run("Collect Garbage");
		exit(message);
	}
	function runDemo() { /* Generates standard imageJ demo blob analysis */
	    run("Blobs (25K)");
		setThreshold(126, 255);
		run("Set Scale...", "distance=10 known=1 unit=um"); /* Add an arbitray scale to demonstrate unit usage. */
		run("Convert to Mask");
		run("Analyze Particles...", "display clear add");
		resetThreshold();
	}
	function stripExtensionsFromString(string) {
		while (lastIndexOf(string, ".")!=-1) {
			index = lastIndexOf(string, ".");
			string = substring(string, 0, index);
		}
		return string;
	}
	function stripUnitFromString(string) {
		if (endsWith(string,"\)")) { /* label with units from string string if available */
			unitIndexStart = lastIndexOf(string, "\(");
			unitIndexEnd = lastIndexOf(string, "\)");
			stringUnit = substring(string, unitIndexStart+1, unitIndexEnd);
			unitCheck = matches(stringUnit, ".*[0-9].*");
			if (unitCheck==0) {  /* if it contains a number it probably isn't a unit */
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
		string= replace(string, fromCharCode(181), "u"); /* micrometer units */
		string= replace(string, fromCharCode(197), "Angstrom"); /* angstrom symbol */
		string= replace(string, fromCharCode(0x2009)+"fromCharCode(0x00B0)", "deg"); /* replace thin spaces degrees combination */
		string= replace(string, fromCharCode(0x2009), "_"); /* replace thin spaces  */
		string= replace(string, " ", "_"); /* replace spaces - these can be a problem with image combination */
		string= replace(string, "_\\+", "\\+"); /* clean up autofilenames */
		string= replace(string, "\\+\\+", "\\+"); /* clean up autofilenames */
		string= replace(string, "__", "_"); /* clean up autofilenames */
		return string;
	}
	function unitLabelFromString(string, imageUnit) {
		if (endsWith(string,"\)")) { /* label with units from string string if available */
			unitIndexStart = lastIndexOf(string, "\(");
			unitIndexEnd = lastIndexOf(string, "\)");
			stringUnit = substring(string, unitIndexStart+1, unitIndexEnd);
			unitCheck = matches(stringUnit, ".*[0-9].*");
			if (unitCheck==0) {  /* if it contains a number it probably isn't a unit */
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
