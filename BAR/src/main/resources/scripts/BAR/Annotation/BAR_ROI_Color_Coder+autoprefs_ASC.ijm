/*	Fork of ROI_Color_Coder.ijm  IJ BAR: https://github.com/tferr/Scripts#scripts
	http://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder
	Colorizes ROIs by matching LUT indexes to measurements in the Results table. It is
	complementary to the ParticleAnalyzer (Analyze>Analyze Particles...), generating
	particle-size heat maps. Requires IJ 1.47r.
	Tiago Ferreira, v.5.4 2017.03.10 (add optional log10 scale) + pjl mods 3/13/2017
	 + option to reverse LUT
	 + dialog requester shows min and max values for all measurements to make it easier to choose a range 8/5/2016
	 + optional min and max lines for ramp
	 + optional mean and std. dev. lines for ramp
	 + cleans up previous runs and checks for data
	 + automated units + Legend title orientation choice 10/13-20/16
	 + optional montage that combines the labeled image with the legend 10/1/2016
	This version v170315 (updates to AR v.5.4 version i.e. includes log option)
*/
/* assess required conditions before proceeding */
	requires("1.47r");
	saveSettings;
	close("*Ramp"); /* cleanup: closes previous ramp windows */
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
	checkForRoiManager(); /* macro requires that the objects are in the ROI manager */
	checkForResults(); /* macro requires that there are results to display */
	nROIs = roiManager("count"); /* get number of ROIs to colorize */
	nRES = nResults;
	if (nRES!=nROIs) restoreExit("Exit: Results table \(" + nRES + "\) and ROI Manager \(" + nROIs + "\) mismatch."); /* exit so that this ambiguity can be cleared up */
	if (nROIs<=1) restoreExit("Exit: ROI Manager has only \(" + nROIs + "\) entries."); /* exit so that this ambiguity can be cleared up */
	items = nROIs;
	setBatchMode(true);
	tN = stripExtensionsFromString(t); /* as in N=name could also use File.nameWithoutExtension but that is specific to last opened file */
	tN = unCleanLabel(tN); /* remove special characters to might cause issues saving file */
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
	Dialog.addChoice("Parameter", headingsWithRange, headingsWithRange[1]);
		luts=getLutsList(); /* I prefer this to new direct use of getList used in the recent versions of the BAR macro YMMV */
	Dialog.setInsets(0, 120, 12);
	Dialog.addCheckbox("Log transform (base-10)", false);
	Dialog.addChoice("LUT:", luts, luts[0]);
	Dialog.setInsets(0, 120, 12);
	Dialog.addCheckbox("Reverse LUT?", false); 
	Dialog.setInsets(6, 0, 6);
	Dialog.addMessage("Color Coded Borders or Filled ROIs?");
	Dialog.addNumber("Outlines or ROIs?", 0, 0, 3, " Width in pixels \(0 to fill ROIs\)");
	Dialog.addSlider("Coding opacity (%):", 0, 100, 100);
	Dialog.setInsets(12, 0, 6);
	Dialog.addMessage("Legend \(ramp\):______________");
	getPixelSize(unit, pixelWidth, pixelHeight);
	unitChoice = newArray("Auto", "Manual", unit, unit+"^2", "None", "pixels", "pixels^2", fromCharCode(0x00B0), "degrees", "radians", "%", "arb.");
	Dialog.addChoice("Unit \("+unit+"\) Label:", unitChoice, unitChoice[0]);
	Dialog.setInsets(-42, 197, -5);
	Dialog.addMessage("Auto based on\nselected parameter");
	Dialog.addString("Range:", "AutoMin-AutoMax", 11);
	Dialog.setInsets(-35, 235, 0);
	Dialog.addMessage("(e.g., 10-100)");
	Dialog.addNumber("No. of labels:", 10, 0, 3, "(Defines major ticks interval)");
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
		useLog = Dialog.getCheckbox;
		lut= Dialog.getChoice;
		revLut= Dialog.getCheckbox;
		stroke= Dialog.getNumber;
		alpha= pad(toHex(255*Dialog.getNumber/100));
		unitLabel = Dialog.getChoice();
		rangeS = Dialog.getString; /* changed from original to allow negative values - see below */
		numLabels = Dialog.getNumber;
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
		statsRampTicks= Dialog.getNumber;
		thinLinesFontSTweak= Dialog.getNumber;
//
	if (rotLegend && rampChoice==rampH) rampH = imageHeight - 2 * fontSize; /* tweaks automatic height selection for vertical legend */
	else rampH = rampChoice;	
//
	range = split(rangeS, "-");
	if (range.length==1) {
		min= NaN;
		max= parseFloat(range[0]);
	} else {
		min= parseFloat(range[0]);
		max= parseFloat(range[1]);
	}
	if (indexOf(rangeS, "-")==0) min = 0 - min; /* checks to see if min is a negative value (lets hope the max isn't). */
	
	fontSR2 = fontSize * thinLinesFontSTweak/100;
	rampLW = maxOf(1, round(rampH/512)); /* ramp line width with a minimum of 1 pixel */
	minmaxLW = round(rampLW / 4); /* line widths for ramp stats */
	
	/* get values for chosen parameter */
	values= newArray(items);
	if (parameter!="Object"){
		for (i=0; i<items; i++) {
			if (useLog) values[i] = log(getResult(parameter,i)) / log(10);
			else values[i] = getResult(parameter,i);
		}
	}
	else for (i=0; i<items; i++) values[i] = i+1;
	Array.getStatistics(values, arrayMin, arrayMax, arrayMean, arraySD); 
	if (useLog) {
		log10AMin = arrayMin;
		arrayMin = pow(10,arrayMin);
		log10AMax = arrayMax;
		arrayMax = pow(10,arrayMax);
		log10PlusSD = arrayMean+arraySD;
		plusSD = pow(10,(log10PlusSD));
		log10MinusSD = arrayMean-arraySD;
		minusSD = pow(10,(log10MinusSD));
		log10Mean = arrayMean;
		arrayMean = pow(10,arrayMean);
		upSD = plusSD - arrayMean;
		downSD = arrayMean - minusSD;
		upCoeffVar = upSD*100/arrayMean;
		downCoeffVar = downSD*100/arrayMean;
		if (min==0) min = arrayMin;  /* override with real min for log scale if zero set manually */
	}
	else coeffVar = arraySD*100/arrayMean;
	if (isNaN(min)) min= arrayMin;
	if (isNaN(max)) max= arrayMax;
	displayedRange = max-min;
	sortedValues = Array.copy(values); sortedValues = Array.sort(sortedValues); /* all this effort to get the median without sorting the original array! */
	arrayMedian = sortedValues[round(items/2)];  /* you could extend this obviously to provide quartiles but at that point you might as well use Excel */
	if (useLog) {
		log10Median = arrayMedian;
		arrayMedian = pow(10,arrayMedian);
		log10Min =  log(min)/log(10);
		log10Max = log(max)/log(10);
		log10DisplayedRange = log10Max - log10Min;
	}
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
	if (useLog) {
		if (statsRampLines)
			unitLabel = unitLabel + " (log10 Stats)";
		else
			unitLabel = unitLabel + " (log10 Distribution)";
	}	
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
//
	/* draw ticks and values */
	step = rampH;
	if (numLabels>2) step /= (numLabels-1);
    setLineWidth(rampLW);
	/* now to see if the selected range values are within 98% of actual */
	if (arrayMin-min>0.02*displayedRange) minIOR = true; /* true minimum is signficantly above ramp minimum */
	else minIOR = false;
	if (max-arrayMax>0.02*displayedRange) maxIOR = true; /* true maximum is signficantly below ramp maximum */
	else maxIOR = false;
	if (min-arrayMin>0.02*displayedRange) minOOR = true; /* true minimum is signficantly below ramp minimum */
	else minOOR = false;
	if (arrayMax-max>0.02*displayedRange) maxOOR = true; /* true maximum is signficantly below ramp maximum */
	else maxOOR = false;
	if (maxOOR && minOOR) minmaxLines = false;
//
	if (useLog) log10Incr = log10DisplayedRange/(numLabels-1);
//
	for (i=0; i<numLabels; i++) {
		yPos = floor(fontSize/2 + rampH - i*step + 1.5*fontSize);
		if (!useLog) rampLabel= min + (displayedRange)/(numLabels-1) * i;
		else rampLabel= pow(10,(log10Min+(log10Incr * i)));
		rampLabelString = removeTrailingZerosAndPeriod(d2s(rampLabel,decPlaces));
		/*Now add overrun text labels at the top and/or bottom of the ramp if the true data extends beyond the ramp range */
		if (minOOR && i==0) {
			/*Now add overrun text labels at the bottom of the ramp if the true data extends below the ramp range */
			rampExt = removeTrailingZerosAndPeriod(d2s(arrayMin,decPlaces+1)); /* adding 1 to dp ensures that the range is different */
			rampLabelString = rampExt + "-" + rampLabelString; 
		}
		if (maxOOR && i==numLabels-1) {
			/*Now add overrun text labels at the top of the ramp if the true data extends above the ramp range */
			rampExt = removeTrailingZerosAndPeriod(d2s(arrayMax,decPlaces+1));
			rampLabelString += "-" + rampExt; 
		}
		drawString(rampLabelString, rampW+4, round(yPos+fontSize/2));
		if (ticks && i>0 && i<numLabels-1) {
			drawLine(0, yPos, tickL, yPos);					/* left tick */
			drawLine(rampW-1-tickL, yPos, rampW+rampLW, yPos); /* right tick extends over border slightly as subtle cross-tick */
		}
	}
	/* now add lines and the true min and max and for stats if chosen in previous dialog */
	rampVOffset = 2 * fontSize;
	if (minmaxLines || statsRampLines) {
		newImage("label_mask", "8-bit black", getWidth(), getHeight(), 1);
		setColor("white");
		setLineWidth(rampLW);
		if (minmaxLines) {
			if (min==max) restoreExit("Something terribly wrong with this range!");
			if (!useLog) trueMaxFactor = (arrayMax-min)/(displayedRange);
			else trueMaxFactor = (log10AMax-log10Min)/(log10DisplayedRange);
			maxPos= round(rampVOffset + (rampH * (1 - trueMaxFactor)));
			if (!useLog) trueMinFactor = (arrayMin-min)/(displayedRange);
			else  trueMinFactor = (log10AMin-log10Min)/(log10DisplayedRange);
			minPos= round(rampVOffset + (rampH * (1 - trueMinFactor)));
			if (trueMaxFactor<0.98) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("Max", round((rampW-getStringWidth("Max"))/2), round(maxPos+0.5*fontSR2));
				drawLine(rampLW, maxPos, tickLR, maxPos);
				drawLine(rampW-1-tickLR, maxPos, rampW-rampLW-1, maxPos);
			}
			if (trueMinFactor>0.02) {
				setFont(fontName, fontSR2, fontStyle);
				drawString("Min", round((rampW-getStringWidth("Min"))/2), round(minPos+0.5*fontSR2));
				drawLine(rampLW, minPos, tickLR, minPos);
				drawLine(rampW-1-tickLR, minPos, rampW-rampLW-1, minPos);
			}
		}
		if (statsRampLines) {
			if (!useLog) meanFactor = (arrayMean-min)/(displayedRange);
			else meanFactor = (log10Mean-log10Min)/(log10DisplayedRange);
			if (useLog) {
				plusSDFactor = (log10PlusSD-log10Min)/(log10DisplayedRange);
				minusSDFactor = (log10MinusSD-log10Min)/(log10DisplayedRange);
			}else{
				plusSDFactor = (arrayMean+arraySD-min)/(displayedRange);
				minusSDFactor = (arrayMean-arraySD-min)/(displayedRange);
			}
			meanPos= round(rampVOffset + (rampH * (1 - meanFactor)));
			plusSDPos= round(rampVOffset + (rampH * (1 - plusSDFactor)));
			minusSDPos= round(rampVOffset + (rampH * (1 - minusSDFactor)));
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
	if (useLog) {
		legendMin = log10Min;
		legendMax = log10Max;
	}else {
		legendMin = min;
		legendMax = max;
	}
	for (countNaN=0, i=0; i<items; i++) {
		showStatus("Coloring object " + i + ", " + (nROIs-i) + " more to go");
		if (isNaN(values[i])) countNaN++;
		if (values[i]<=legendMin)
			lutIndex= 0;
		else if (values[i]>legendMax)
			lutIndex= 255;
		else if (!revLut)
			lutIndex= round(255 * (values[i] - legendMin) / (legendMax - legendMin));
		else {
			if (values[i]<=legendMin) lutIndex= 255;
			else if (values[i]>legendMax) lutIndex= 0;
			else lutIndex= round(255 * (legendMax - values[i]) / (legendMax - legendMin));
		}
		roiManager("select", i);
		if (stroke>0) {
			roiManager("Set Line Width", stroke);
			roiManager("Set Color", alpha+roiColors[lutIndex]);
		} else
			roiManager("Set Fill Color", alpha+roiColors[lutIndex]);
	}
/*
	display result */
	roiManager("Show all");
	if (countNaN!=0)
		print("\n>>>> ROI Color Coder:\n"
			+ "Some values from the \""+ parameter +"\" column could not be retrieved.\n"
			+ countNaN +" ROI(s) were labeled with a default color.");
	roiManager("Show All without labels");
	
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
		selectWindow(t);
		run("Flatten");
		if (originalImageDepth==8 && lut=="Grays") run("8-bit"); // restores gray if all gray settings
		rename(tN + "_" + parameterLabel + "_coded");
		tNC = getTitle();
		if (createCombo=="Combine Scaled Ramp with New Image" || createCombo=="Combine Ramp with New Image") run("Duplicate...", "title=temp_combo");
		run("Canvas Size...", "width="+comboW+" height="+imageHeight+" position=Top-Left");
		makeRectangle(imageWidth, round((imageHeight-canvasH)/2), srW, imageHeight);
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Scaled Ramp with New Image") run("Image to Selection...", "image=scaled_ramp opacity=100");
		else  run("Image to Selection...", "image=" + tR + " opacity=100"); /* can use "else" here because we have already eliminated the "No" option */
		run("Flatten");
		if (originalImageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
		if (!useLog) rename(tNC + "+ramp");
		else rename(tNC + "+log10-ramp");
		closeImageByTitle("scaled_ramp");
		closeImageByTitle("temp_combo");
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Ramp with Current") closeImageByTitle(tNC);
	}
	
	else run("Flatten");
	if (originalImageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
	restoreSettings;
	setBatchMode("exit & display");	
	showStatus("BAR ROI Color Coder + Autoprefs Macro Finished");
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
			else restoreExit("Goodbye, your previous setting will be restored.");
		}
	}
	function checkForRoiManager() {
		/* v161109 adds the return of the updated ROI count and also adds dialog if there are already entries just in case . . */
		nROIs = roiManager("count");
		nRES = nResults; /* not really needed except to provide useful information below */
		if (nROIs==0) runAnalyze = true;
		else runAnalyze = getBoolean("There are already " + nROIs + " in the ROI manager; do you want to clear the ROI manager and reanalyze?");
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
	function pad(n) {
		n= toString(n); if (lengthOf(n)==1) n= "0"+n; return n;
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
		restoreSettings(); /* clean up before exiting */
		setBatchMode("exit & display"); /* not sure if this does anything useful if exiting gracefully but otherwise harmless */
		exit(message);
	}
	function runDemo() { /* Generates standard imageJ demo blob analysis */
	    run("Blobs (25K)");
		setThreshold(126, 255);
		run("Set Scale...", "distance=10 known=1 unit=um"); /* Add an arbitray scale to demonstrate unit usage. */
		run("Convert to Mask");
		// run("Analyze Particles...", "display clear add");
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
