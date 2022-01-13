/*	Fork of ROI_Color_Coder.ijm  IJ BAR: https://github.com/tferr/Scripts#scripts
	http://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder
	Colorizes ROIs by matching LUT indexes to measurements in the Results table. It is
	Tiago Ferreira, v.5.2 2015.08.13 -	v.5.3 2016.05.1 + pjl mods 6/16-30/2016 to automate defaults and add labels to ROIs
	v211104
*/
 
macro "ROI Color Coder with Labels"{
	macroL = "BAR_ROI_Color_Coder+ROI-Manager-Labels_ASC_v211112.ijm";
	requires("1.53g"); /* Uses expandable arrays */
	if (!checkForPluginNameContains("Fiji_Plugins")) exit("Sorry this macro requires some functions in the Fiji_Plugins package");
	/* Needs Fiji_plugins for autoCrop */
	saveSettings;
	imageN = nImages;
	/* Some cleanup */
	close("*Ramp"); /* closes previous ramp windows */  
	if (imageN==0){
		showMessageWithCancel("No images open or the ROI Manager is empty...\n"
        + "Run demo? (Results Table and ROI Manager will be cleared)");
	    runDemo();
	}
	run("Select None");
	/*
	Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1");						 /* Set the background to white */
	run("Colors...", "foreground=black background=white selection=yellow"); /* Set the preferred colors for these macros */
	setOption("BlackBackground", false);
	run("Appearance...", " "); if(is("Inverting LUT")) run("Invert LUT"); /* do not use Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background)
		http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	id = getImageID(); /* get id of image and title */
	t = getTitle();
	checkForUnits(); /* Required function */
	getPixelSize(unit, pixelWidth, pixelHeight);									
	checkForRoiManager(); /* macro requires that the objects are in the ROI manager */
	checkForResults(); /* macro requires that there are results to display */
	nROIs = roiManager("count"); /* get number of ROIs to colorize */
	nRES = nResults;
	menuLimit = 0.8 * screenHeight; /* used to limit menu size for small screens */	  
	if (nRES!=nROIs) restoreExit("Exit: Results table \(" + nRES + "\) and ROI Manager \(" + nROIs + "\) mismatch."); /* exit so that this ambiguity can be cleared up */
	if (nROIs<=1) restoreExit("Exit: ROI Manager has only \(" + nROIs + "\) entries."); /* exit so that this ambiguity can be cleared up */
	items = nROIs;
	run("Remove Overlay");
	setBatchMode(true);
	tN = stripKnownExtensionFromString(t); /* as in N=name could also use File.nameWithoutExtension but that is specific to last opened file */
	tN = unCleanLabel(tN); /* remove special characters and spaces that might cause issues saving file */
	if (lengthOf(tN)>43) tNL = substring(tN,0,21) + "..." + substring(tN, lengthOf(tN)-21);
	else tNL = tN;
	imageHeight = getHeight(); imageWidth = getWidth();
	rampH = round(0.88 * imageHeight); /* suggest ramp slightly small to allow room for labels */
	fontSize = maxOf(10,imageHeight/28); /* default fonts size based on imageHeight */
	imageDepth = bitDepth(); /* required for shadows at different bit depths */
	
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
	numIntervals = 10; /* default interval number */
	/* create the dialog prompt */
	Dialog.create("Macro: " + macroL);
	if (menuLimit > 752) {  /* menu bloat allowed only for small screens */										 
		Dialog.setInsets(6, 0, -5);
		Dialog.addMessage("Filename: " + tNL);
		Dialog.setInsets(6, 0, 6);
	}						
	Dialog.addChoice("Parameter", headingsWithRange, headingsWithRange[1]);
		luts=getLutsList(); /* I prefer this to new direct use of getList used in the recent versions of the BAR macro YMMV */
	Dialog.addChoice("LUT:", luts, luts[0]);
	Dialog.setInsets(0, 120, 12);
	Dialog.addCheckbox("Reverse LUT?", false); 
	Dialog.setInsets(6, 0, 6);
	Dialog.addMessage("Color Coded Borders or Filled ROIs?");
	Dialog.addNumber("Outlines or ROIs?", 0, 0, 3, " Width in pixels \(0 to fill ROIs\)");
	Dialog.addSlider("Coding opacity (%):", 0, 100, 100);
	Dialog.setInsets(12, 0, 6);
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
	Dialog.addNumber("No. of intervals:", numIntervals, 0, 3, "Major label count will be +1 more than this");
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
	Dialog.addCheckbox("Force legend label to right of and || to ramp", false);
	Dialog.setInsets(4, 120, 0);
	Dialog.addCheckbox("Stats: Add labels at mean and " + fromCharCode(0x00B1) + " SD", false);
	Dialog.addNumber("Tick length:", 50, 0, 3, "% of major tick. Also Min. & Max. Lines");
	Dialog.addNumber("Stats label font:", 100, 0, 3, "% of font size. Also Min. & Max. Lines");
	Dialog.addHelp("http://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder");
	Dialog.show;
		parameterWithLabel= Dialog.getChoice;
		parameter= substring(parameterWithLabel, 0, indexOf(parameterWithLabel, ":  "));
		lut= Dialog.getChoice;
		revLut= Dialog.getCheckbox;
		stroke= Dialog.getNumber;
		alpha= pad(toHex(255*Dialog.getNumber/100));
		unitLabel= Dialog.getChoice();
		rangeS= Dialog.getString; /* changed from original to allow negative values - see below */
		minmaxLines = Dialog.getCheckbox;															 
		numIntervals = Dialog.getNumber; /* The number intervals along ramp */
		numLabels = numIntervals + 1;  /* The number of major ticks/labels is one more than the intervals */
		dpChoice= Dialog.getChoice;
		rampChoice= parseFloat(Dialog.getChoice);
		fontStyle= Dialog.getChoice;
			if (fontStyle=="unstyled") fontStyle="";
		fontName= Dialog.getChoice;
		fontSize= Dialog.getNumber;
		ticks= Dialog.getCheckbox;
		rotLegend= Dialog.getCheckbox;
		statsRampLines= Dialog.getCheckbox;
		statsRampTickL= Dialog.getNumber;
		thinLinesFontSTweak= Dialog.getNumber;
	
	if (rotLegend && rampChoice==rampH) rampH = imageHeight - 2 * fontSize; /* tweaks automatic height selection for vertical legend */
	else rampH = rampChoice;
	
	range = split(rangeS, "-");
	if (lengthOf(range)==1) {
		rampMin= NaN; rampMax= parseFloat(range[0]);
	} else {
		rampMin= parseFloat(range[0]); rampMax= parseFloat(range[1]);
	}
	if (indexOf(rangeS, "-")==0) rampMin = 0 - rampMin; /* checks to see if rampMin is a negative value (lets hope the max isn't). */
	
	fontSR2 = fontSize * thinLinesFontSTweak/100;
	rampLW = maxOf(1, round(rampH/512)); /* ramp line width with a minimum of 1 pixel */
	minmaxLW = round(rampLW / 4); /* line widths for ramp stats */
	
	/* get values for chosen parameter */
	values= newArray(items);
	if (parameter!="Object"){
		for (i=0; i<items; i++) {
			values[i] = getResult(parameter,i);
		}
	}
	else for (i=0; i<items; i++) values[i] = i+1;
	Array.getStatistics(values, arrayMin, arrayMax, arrayMean, arraySD);
	if (isNaN(rampMin)) rampMin= arrayMin;
	if (isNaN(rampMax)) rampMax= arrayMax;
	displayedRange = rampMax-rampMin;
	coeffVar = arraySD*100/arrayMean;
	sortedValues = Array.copy(values); sortedValues = Array.sort(sortedValues); /* all this effort to get the median without sorting the original array! */
	arrayMedian = sortedValues[round(items/2)];  /* you could extend this obviously to provide quartiles but at that point you might as well use Excel */
	
/* Create the parameter label */
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
/*
		Create LUT-map legend
*/
	rampW = round(rampH/8); canvasH = round(4 * fontSize + rampH); canvasW = round(rampH/2); tickL = round(rampW/4);
	if (statsRampLines || minmaxLines) tickL = round(tickL/2); /* reduce tick length to provide more space for inside label */
	tickLR = round(tickL * statsRampTickL/100);
	getLocationAndSize(imgx, imgy, imgwidth, imgheight);
	call("ij.gui.ImageWindow.setNextLocation", imgx + imgwidth, imgy);
	
	newImage(tN + "_" + parameterLabel +"_Ramp", "8-bit ramp", rampH, rampW, 1);
	tR = getTitle; /* short variable label for ramp */
	
	roiColors= loadLutColors(lut); /* load the LUT as a hexColor array: requires function */
	/* continue the legend design */
	setColor(0, 0, 0);
	setBackgroundColor(255, 255, 255);
	setFont(fontName, fontSize, fontStyle);
	if (imageDepth!=8 || lut!="Grays") run("RGB Color"); /* converts ramp to RGB if not using grays only */
	setLineWidth(rampLW*2);
	if (ticks) drawRect(0, 0, rampH, rampW);
	
	if (!revLut) run("Rotate 90 Degrees Left");
	else run("Rotate 90 Degrees Right");
	run("Canvas Size...", "width=&canvasW height=&canvasH position=Center-Left");
	
	if (dpChoice=="Auto")
		decPlaces = autoCalculateDecPlaces3(rampMin,rampMax,numIntervals);
	else if (dpChoice=="Manual") 
		decPlaces=getNumber("Choose Number of Decimal Places", 0);
	else if (dpChoice=="Scientific")
		decPlaces = -1;
	else decPlaces = dpChoice;
	
	/* draw ticks and values */
	step = rampH;
	if (numLabels>2) step /= (numIntervals);
	setLineWidth(rampLW);
	/* now to see if the selected range values are within 98% of actual */
	if (0.98*rampMin>arrayMin || rampMax<0.98*arrayMax) minmaxOOR = true;
	else minmaxOOR = false;
	if (rampMin<0.98*arrayMin || 0.98*rampMax>arrayMax) minmaxIOR = true;
	else minmaxIOR = false;
	if (minmaxIOR && minmaxLines) minmaxLines = true;
	else minmaxLines = false;
	for (i=0; i<numLabels; i++) {
		yPos= floor(fontSize/2 + rampH - i*step + 1.5*fontSize);
		rampLabel = rampMin + (displayedRange)/(numLabels-1) * i;
		rampLabelString = removeTrailingZerosAndPeriod(d2s(rampLabel,decPlaces));
if (minmaxIOR) {
			/*Now add overrun text labels at the top and/or bottom of the ramp if the true data extends beyond the ramp range */
			if (i==0 && (0.98*rampMin)>arrayMin) {
				rampExt = removeTrailingZerosAndPeriod(d2s(arrayMin,decPlaces+1)); /* adding 1 to dp ensures that the range is different */
				rampLabelString = rampExt + "-" + rampLabelString; 
			}if (i==numLabels-1 && (1.02*rampMax)<arrayMax) {
				rampExt = removeTrailingZerosAndPeriod(d2s(arrayMax,decPlaces+1));
				rampLabelString += "-" + rampExt; 
			}
		}
		drawString(rampLabelString, rampW+4*rampLW, round(yPos+fontSize/2));
		if (ticks) {
			if (i==0 || i==numLabels-1) {
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
	if (minmaxLines || statsRampLines) {
		newImage("label_mask", "8-bit black", getWidth(), getHeight(), 1);
		setColor("white");
		setLineWidth(rampLW);
		if (minmaxLines) {
			if (rampMin==rampMax) restoreExit("Something terribly wrong with this range!");
			trueMaxFactor = (arrayMax-rampMin)/(displayedRange);
			maxPos= round(fontSize/2 + (rampH * (1 - trueMaxFactor)) +1.5*fontSize);
			trueMinFactor = (arrayMin-rampMin)/(displayedRange);
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
			meanFactor = (arrayMean-rampMin)/(displayedRange);
			plusSDFactor =  (arrayMean+arraySD-rampMin)/(displayedRange);
			minusSDFactor =  (arrayMean-arraySD-rampMin)/(displayedRange);
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
	/* now use a mask to create black outline around white text to stand out against ramp colors */
	rampOutlineStroke = round(rampLW/2);
	setThreshold(0, 128);
	setOption("BlackBackground", false);
	run("Convert to Mask");
	selectWindow(tR);
	run("Select None");
	getSelectionFromMask("label_mask");
	run("Enlarge...", "enlarge=[rampOutlineStroke] pixel");
	setBackgroundColor(0,0,0);
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
	
/*	parse symbols in unit and draw final label below ramp or next to ramp */
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
		if (rampUnitLabel!="") rampParameterLabel += ", " + rampUnitLabel;
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
	
	lcf=(pixelWidth+pixelHeight)/2; /* length conversion factor needed for morph. centroids */
	/*
		iterate through the ROI Manager list and colorize ROIs
	*/
	selectImage(id);
	for (countNaN=0, i=0; i<items; i++) {
		showStatus("Coloring object " + i + ", " + (nROIs-i) + " more to go");
		if (isNaN(values[i])) countNaN++;
		if (!revLut) {
			if (values[i]<=rampMin) lutIndex= 0;
			else if (values[i]>rampMax) lutIndex= 255;
			else lutIndex= round(255 * (values[i] - rampMin) / (rampMax - rampMin));
		}
		else {
			if (values[i]<=rampMin) lutIndex= 255;
			else if (values[i]>rampMax) lutIndex= 0;
			else lutIndex= round(255 * (rampMax - values[i]) / (rampMax - rampMin));
		}
		roiManager("select", i);
		if (stroke>0) {
			roiManager("Set Line Width", stroke);
			roiManager("Set Color", alpha+roiColors[lutIndex]);
		} else
			roiManager("Set Fill Color", alpha+roiColors[lutIndex]);
		labelValue = values[i];
		labelString = d2s(labelValue,decPlaces); /* Reduce decimal places for labeling (move these two lines to below the labels you prefer) */
		labelString = removeTrailingZerosAndPeriod(labelString); /* Remove trailing zeros and periods */
		roiManager("Rename", labelString); /* label roi with feature value */
	}
	
	/* display result */
	roiManager("show all");
	if (countNaN!=0)
		print("\n>>>> ROI Color Coder:\n"
			+ "Some values from the \""+ parameter +"\" column could not be retrieved.\n"
			+ countNaN +" ROI(s) were labeled with a default color.");
	roiManager("show all with labels");
	roiManager("UseNames", "true");
	run("Flatten");
	if (imageDepth==8 && lut=="Grays") run("8-bit"); // restores gray if all gray settings
	rename(tN + "_" + parameterLabel + "_coded");
	tNC = getTitle();
//
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
			run("Scale...", "x=&rampScale y=&rampScale interpolation=Bicubic average create title=scaled_ramp");
			canvasH = getHeight(); /* update ramp height */
		}
		srW = getWidth;
		comboW = srW + imageWidth;
		selectWindow(tNC);
		if (createCombo=="Combine Scaled Ramp with New Image" || createCombo=="Combine Ramp with New Image") run("Duplicate...", "title=temp_combo");
		run("Canvas Size...", "width="+comboW+" height="+imageHeight+" position=Top-Left");
		makeRectangle(imageWidth, round((imageHeight-canvasH)/2), srW, imageHeight);
		setBatchMode("exit & display");
		wait(10); /* required to get image to selection to work here */
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Scaled Ramp with New Image") run("Image to Selection...", "image=scaled_ramp opacity=100");
		else run("Image to Selection...", "image=" + tR + " opacity=100"); /* can use "else" here because we have already eliminated the "No" option */
		run("Flatten");
		if (imageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
		rename(tNC + "+ramp");
		closeImageByTitle("scaled_ramp");
		closeImageByTitle("temp_combo");
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Ramp with Current") closeImageByTitle(tNC);
	}

	setBatchMode("exit & display");
	restoreSettings;
	call("java.lang.System.gc"); 
	showStatus(macroL + " Macro Finished");
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
			NOTE: requires ASC restoreExit function which requires previous run of saveSettings */
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
			subFolderList = newArray;
			for (i=0,countSF=0; i<lengthOf(pluginList); i++) {
				if (endsWith(pluginList[i], "/")){
					subFolderList = subFolderList[countSF] = pluginList[i];
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
	function expandLabel(string) {  /* Expands abbreviations typically used for compact column titles
		v200604	fromCharCode(0x207B) removed as superscript hyphen not working reliably
		v211102-v211103  Some more fixes and updated to match latest extended geometries  */
		string = replace(string, "Raw Int Den", "Raw Int. Density");
		string = replace(string, "FeretAngle", "Feret Angle");
		string = replace(string, "FiberThAnn", "Fiber Thckn. from Annulus");
		string = replace(string, "FiberLAnn", "Fiber Length from Annulus");
		string = replace(string, "FiberLR", "Fiber Length R");
		string = replace(string, " Th ", " Thickness ");
		string = replace(string, " Crl ", " Curl ");
		string = replace(string, "Snk", "\(Snake\)");
		string = replace(string, "Fbr", "Fiber");
		string = replace(string, "Cir_to_El_Tilt", "Circle Tilt based on Ellipse");
		string = replace(string, "AR_", "Aspect Ratio: ");
		string = replace(string, "Rnd_", "Roundness: ");
		string = replace(string, "Sqr_", "Square: ");
		string = replace(string, "Squarity_AP","Squarity: from Area and Perimeter");
		string = replace(string, "Squarity_AF","Squarity: from Area and Feret");
		string = replace(string, "Squarity_Ff","Squarity: from Feret");
		string = replace(string, "Rss1", "/(Russ Formula 1/)");
		string = replace(string, "Rss1", "/(Russ Formula 2/)");
		string = replace(string, "Rndnss", "Roundness");
		string = replace(string, "_cAR", "\(Corrected by Aspect Ratio\)");
		string = replace(string, "Da_Equiv","Diameter from Area \(Circular\)");
		string = replace(string, "Dp_Equiv","Diameter from Perimeter \(Circular\)");	
		string = replace(string, "Dsph_Equiv","Diameter from Feret \(Spherical\)");
		string = replace(string, "Hxgn_", "Hexagon: ");
		string = replace(string, "Perim", "Perimeter");
		string = replace(string, "Perimetereter", "Perimeter"); /* just in case we already have a perimeter */
		string = replace(string, "HSFR", "Hexagon Shape Factor Ratio");
		string = replace(string, "HSF", "Hexagon Shape Factor");
		string = replace(string, "Vol_", "Volume: ");
		string = replace(string, "Da", "Diam:area");
		string = replace(string, "Dp", "Diam:perim.");
		string = replace(string, "equiv", "equiv.");
		string = replace(string, "_", " ");
		string = replace(string, "°", "degrees");
		string = replace(string, "0-90", "0-90°"); /* An exception to the above */
		string = replace(string, "°, degrees", "°"); /* That would be otherwise be too many degrees */
		string = replace(string, fromCharCode(0x00C2), ""); /* Remove mystery Â */
		// string = replace(string, "^-", fromCharCode(0x207B)); /* Replace ^- with superscript - Not reliable though */
		// string = replace(string, " ", fromCharCode(0x2009)); /* Use this last so all spaces converted */
		return string;
	}
	function getLutsList() {
		/* v180723 added check for preferred LUTs
			v210430 expandable array version   v211029 added cividis.lut  */
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
		n= toString(n); if (lengthOf(n)==1) n= "0"+n; return n;
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
		*/
		string = "" + string;
		if (lastIndexOf(string, ".")>0 || lastIndexOf(string, "_lzw")>0) {
			knownExt = newArray("dsx", "DSX", "tif", "tiff", "TIF", "TIFF", "png", "PNG", "GIF", "gif", "jpg", "JPG", "jpeg", "JPEG", "jp2", "JP2", "txt", "TXT", "csv", "CSV","xlsx","XLSX","_"," ");
			kEL = lengthOf(knownExt);
			chanLabels = newArray("\(red\)","\(green\)","\(blue\)");
			unwantedSuffixes = newArray("_lzw"," ","  ", "__","--","_","-");
			uSL = lengthOf(unwantedSuffixes);
			for (i=0; i<kEL; i++) {
				for (j=0; j<3; j++){ /* Looking for channel-label-trapped extensions */
					ichanLabels = lastIndexOf(string, chanLabels[j]);
					if(ichanLabels>0){
						index = lastIndexOf(string, "." + knownExt[i]);
						if (ichanLabels>index && index>0) string = "" + substring(string, 0, index) + "_" + chanLabels[j];
						ichanLabels = lastIndexOf(string, chanLabels[j]);
						for (k=0; k<uSL; k++){
							index = lastIndexOf(string, unwantedSuffixes[k]);  /* common ASC suffix */
							if (ichanLabels>index && index>0) string = "" + substring(string, 0, index) + "_" + chanLabels[j];	
						}				
					}
				}
				index = lastIndexOf(string, "." + knownExt[i]);
				if (index>=(lengthOf(string)-(lengthOf(knownExt[i])+1)) && index>0) string = "" + substring(string, 0, index);
			}
		}
		unwantedSuffixes = newArray("_lzw"," ","  ", "__","--","_","-");
		for (i=0; i<lengthOf(unwantedSuffixes); i++){
			sL = lengthOf(string);
			if (endsWith(string,unwantedSuffixes[i])) string = substring(string,0,sL-lengthOf(unwantedSuffixes[i])); /* cleanup previous suffix */
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
	+ 041117b to remove spaces as well */
		string= replace(string, fromCharCode(178), "\\^2"); /* superscript 2 */
		string= replace(string, fromCharCode(179), "\\^3"); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, fromCharCode(0xFE63) + fromCharCode(185), "\\^-1"); /* Small hyphen substituted for superscript minus as 0x207B does not display in table */
		string= replace(string, fromCharCode(0xFE63) + fromCharCode(178), "\\^-2"); /* Small hyphen substituted for superscript minus as 0x207B does not display in table */
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
	/* History:
	+ add ability to reverse LUT and also shows min and max values for all measurements to make it easier to choose a range 8/5/2016
 	+ min and max lines for ramp
	+ added option to make a new combined image that combines the labeled image with the legend 10/1/2016
	+ added the ability to add lines on ramp for statistics
	+ v161117 adds more decimal place control
	+ v170914 Added garbage clean up as suggested by Luc LaLonde at LBNL.
	+ Update functions to latest versions.
	+ v180316 Reordered 1st menu.
	+ v180723 Minor updates to LUTs list function.
	+ v180831 Added check for Fiji_Plugins.	
	+ v200706 Change imageDepth variable name added macro label.
	+ v210427-v210503 Updated to match other ASC macros.
	+ v211025 Updated functions
	+ v211029 Added cividis.lut
	+ v211103 Expanded expandLabels function
	+ v211104: Updated stripKnownExtensionsFromString function    v211112: Again
	*/