
/*	Fork of ROI_Color_Coder.ijm  IJ BAR: https://github.com/tferr/Scripts#scripts
	http://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder
	Colorizes ROIs by matching LUT indexes to measurements in the Results table. It is
	Tiago Ferreira, v.5.2 2015.08.13 -	v.5.3 2016.05.1 + pjl mods 6/16-30/2016 to automate defaults and add labels to ROIs
	+ add ability to reverse LUT and also shows min and max values for all measurements to make it easier to choose a range 8/5/2016
 	+ min and max lines for ramp
	+ added option to make a new combined image that combines the labeled image with the legend 10/1/2016
	+ added the ability to add lines on ramp for statistics
	+ v161117 adds more decimal place control
	+ v170914 Added garbage clean up as suggested by Luc LaLonde at LBNL.
	+ Update functions to latest versions.
 */
macro "ROI Color Coder with Labels"{
	requires("1.47r");
	saveSettings;
	/* Some cleanup */
	close("*Ramp"); /* closes previous ramp windows */  
	if (nImages==0){
		showMessageWithCancel("No images open or the ROI Manager is empty...\n"
        + "Run demo? (Results Table and ROI Manager will be cleared)");
	    runDemo();
	}		   
	run("Select None");
	/*
	Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* set white background */
	run("Colors...", "foreground=black background=white selection=yellow"); /* set colors */
	setOption("BlackBackground", false);
	run("Appearance...", " "); /* do not use Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background)
		http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	id = getImageID();	t=getTitle(); /* get id of image and title */
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
	
	setBatchMode(true);
	tN = stripExtensionsFromString(t); /* as in N=name could also use File.nameWithoutExtension but that is specific to last opened file */
	tN = unCleanLabel(tN); /* remove special characters and spaces that might cause issues saving file */
	imageHeight = getHeight(); imageWidth = getWidth();
	rampH = round(0.88 * imageHeight); /* suggest ramp slightly small to allow room for labels */
	fontSize = rampH/28; /* default fonts size based on imageHeight */
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
		headingsWithRange[0] = "ID" + ":  1 - " + items; /* relabels ImageJ ID column */
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
	Dialog.addNumber("No. of intervals:", 10, 0, 3, "Defines major ticks/label spacing");
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
		parameterWithLabel= Dialog.getChoice;
		parameter= substring(parameterWithLabel, 0, indexOf(parameterWithLabel, ":  "));
		lut= Dialog.getChoice;
		revLut= Dialog.getCheckbox;
		stroke= Dialog.getNumber;
		alpha= pad(toHex(255*Dialog.getNumber/100));
		unitLabel= Dialog.getChoice();
		rangeS= Dialog.getString; /* changed from original to allow negative values - see below */
		numLabels= Dialog.getNumber + 1; /* The number of major ticks/labels is one more than the intervals */
		dpChoice= Dialog.getChoice;
		rampChoice= parseFloat(Dialog.getChoice);
		fontStyle= Dialog.getChoice;
			if (fontStyle=="unstyled") fontStyle="";
		fontName= Dialog.getChoice;
		fontSize= Dialog.getNumber;
		ticks= Dialog.getCheckbox;
		rotLegend= Dialog.getCheckbox;
		minmaxLines = Dialog.getCheckbox;
		statsRampLines= Dialog.getCheckbox;
		statsRampTicks= Dialog.getNumber;
		thinLinesFontSTweak= Dialog.getNumber;
	
	if (rotLegend && rampChoice==rampH) rampH = imageHeight - 2 * fontSize; /* tweaks automatic height selection for vertical legend */
	else rampH = rampChoice;
	
	range = split(rangeS, "-");
	if (lengthOf(range)==1) {
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
	if (parameter!="Object"){
		for (i=0; i<items; i++) {
			values[i] = getResult(parameter,i);
		}
	}
	else for (i=0; i<items; i++) values[i] = i+1;
	Array.getStatistics(values, arrayMin, arrayMax, arrayMean, arraySD);
	if (isNaN(min)) min= arrayMin;
	if (isNaN(max)) max= arrayMax;
	displayedRange = max-min;
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
	tickLR = round(tickL * statsRampTicks/100);
	getLocationAndSize(imgx, imgy, imgwidth, imgheight);
	call("ij.gui.ImageWindow.setNextLocation", imgx+imgwidth, imgy);
	
	newImage(tN + "_" + parameterLabel +"_Ramp", "8-bit ramp", rampH, rampW, 1);
	tR = getTitle; /* short variable label for ramp */
	
	roiColors= loadLutColors(lut); /* load the LUT as a hexColor array: requires function */
	/* continue the legend design */
	setColor(0, 0, 0);
	setBackgroundColor(255, 255, 255);
	setFont(fontName, fontSize, fontStyle);
	if (originalImageDepth!=8 || lut!="Grays") run("RGB Color"); /* converts ramp to RGB if not using grays only */
	setLineWidth(rampLW*2);
	if (ticks) drawRect(0, 0, rampH, rampW);
	
	if (!revLut) run("Rotate 90 Degrees Left");
	else run("Rotate 90 Degrees Right");
	run("Canvas Size...", "width="+ canvasW +" height="+ canvasH +" position=Center-Left");
	
	if (dpChoice=="Auto")
		decPlaces = autoCalculateDecPlaces(decPlaces);
	else if (dpChoice=="Manual") 
		decPlaces=getNumber("Choose Number of Decimal Places", 0);
	else if (dpChoice=="Scientific")
		decPlaces = -1;
	else decPlaces = dpChoice;
	
	/* draw ticks and values */
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
		yPos= floor(fontSize/2 + rampH - i*step + 1.5*fontSize);
		rampLabel= min + (max-min)/(numLabels-1) * i;
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
				setLineWidth(rampLW); /* reset line width */
			}
		}
	}
	/* now add lines and the true min and max and for stats if chosen in previous dialog */
	if (minmaxLines || statsRampLines) {
		newImage("label_mask", "8-bit black", getWidth(), getHeight(), 1);
		setColor("white");
		setLineWidth(rampLW);
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
	
	lcf=(pixelWidth+pixelHeight)/2; /* length conversion factor needed for morph. centroids */
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
	if (originalImageDepth==8 && lut=="Grays") run("8-bit"); // restores gray if all gray settings
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
			run("Scale...", "x="+rampScale+" y="+rampScale+" interpolation=Bicubic average create title=scaled_ramp");
			canvasH = getHeight(); /* update ramp height */
		}
		srW = getWidth;
		comboW = srW + imageWidth;
		selectWindow(tNC);
		if (createCombo=="Combine Scaled Ramp with New Image" || createCombo=="Combine Ramp with New Image") run("Duplicate...", "title=temp_combo");
		run("Canvas Size...", "width="+comboW+" height="+imageHeight+" position=Top-Left");
		makeRectangle(imageWidth, round((imageHeight-canvasH)/2), srW, imageHeight);
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Scaled Ramp with New Image") run("Image to Selection...", "image=scaled_ramp opacity=100");
		else run("Image to Selection...", "image=" + tR + " opacity=100"); /* can use "else" here because we have already eliminated the "No" option */
		run("Flatten");
		if (originalImageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
		rename(tNC + "+ramp");
		closeImageByTitle("scaled_ramp");
		closeImageByTitle("temp_combo");
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Ramp with Current") closeImageByTitle(tNC);
	}
	restoreSettings;
	setBatchMode("exit & display");
	run("Collect Garbage"); 
	showStatus("ROI Color Coder + Object Labels Macro Finished");
	/*
		   ( 8(|)	( 8(|)	Functions	@@@@@:-)	@@@@@:-)
   */
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
			else restoreExit("Goodbye");
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
	function getLutsList() {
		lutsCheck = 0;
		defaultLuts= getList("LUTs");
		Array.sort(defaultLuts);
		if (getDirectory("luts") == "") restoreExit("Failure to find any LUTs!");
		/* A list of frequently used luts for the top of the list . . . */
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
		return lutsList; /* required to return new array */
	}
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
