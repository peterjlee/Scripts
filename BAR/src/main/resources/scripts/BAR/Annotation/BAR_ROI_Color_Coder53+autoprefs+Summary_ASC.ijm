/*	Fork of ROI_Color_Coder.ijm  IJ BAR: https://github.com/tferr/Scripts#scripts
	http://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder
 	Colorizes ROIs by matching LUT indexes to measurements in the Results table. It is
 	complementary to the ParticleAnalyzer (Analyze>Analyze Particles...), generating
 	particle-size heat maps. Requires IJ 1.47r.
 	Tiago Ferreira, v.5.2 2015.08.13 -	v.5.3 2016.05.1 + pjl mods 6/16/2016
 	 + add ability to reverse LUT and also shows min and max values for all measurements to make it easier to choose a range 8/5/2016
	 + summary.
	 + option to make a new combined image that combines the labeled image with the legend 10/1/2016
	 + automated units + Legend title orientation choice 10/13-20/16
	 + cleans up previous runs and checks for data
	This version v161116 Adds ability to change the number of rows in the table
 */
	requires("1.47r");
	saveSettings;
	/* Some cleanup */
	close("*Ramp"); /* closes previous ramp windows */
		/* Check to see if there is a location already set for the summary */
	if (selectionType()==0) {
		getSelectionBounds(originalSelEX, originalSelEY, originalSelEWidth, originalSelEHeight);
		selectionExists = true;
	}
	else selectionExists = false;
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
	imageHeight = getHeight();
	imageWidth = getWidth();
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
	
	/* create the dialog prompt */
	Dialog.create("ROI Color Coder: " + tN);
	macroP = getInfo("macro.filepath");
	Dialog.setInsets(6, 0, -15);
	Dialog.addMessage("Macro: " + substring(macroP, lastIndexOf(macroP, "\\") + 1, lastIndexOf(macroP, ".ijm" )));
	Dialog.addMessage("Filename: " + tN);
	Dialog.setInsets(6, 0, 6);
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
	getPixelSize(unit, pixelWidth, pixelHeight);
	unitChoice = newArray("Auto", "Manual", unit, unit+"^2", "None", "pixels", "pixels^2", fromCharCode(0x00B0), "degrees", "radians", "%", "arb.");
	Dialog.addChoice("Unit \("+unit+"\) Label:", unitChoice, unitChoice[0]);
	Dialog.setInsets(-42, 197, -5);
	Dialog.addMessage("Auto based on\nselected parameter");
	Dialog.addString("Range:", "AutoMin-AutoMax", 11);
	Dialog.setInsets(-35, 235, 0);
	Dialog.addMessage("(e.g., 10-100)");
	Dialog.addNumber("No. of labels:", 10, 0, 3, "(Defines major ticks interval)");
	Dialog.addChoice("Decimal places:", newArray("Auto", "Manual", "Scientific"), "Auto");
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
	Dialog.setInsets(6, 0, 6);
	Dialog.addMessage("Summary:_________________________________");
	Dialog.setInsets(6, 135, 12);
	Dialog.addCheckbox("Add summary table?", true); 
	Dialog.addNumber("How many rows?", 6, 0, 2, " up to 8 rows in table");
	if (nROIs!=nRES)
		Dialog.addMessage(nROIs +" ROI(s) in Manager, "+ nRES +" rows in Results table:\n"
				+ abs(nROIs-nRES) +" item(s) will be ignored...");
	Dialog.addHelp("http://imagejdocu.tudor.lu/doku.php?id=macro:roi_color_coder");
	Dialog.show;
		parameterWithLabel = Dialog.getChoice;
		parameter = substring(parameterWithLabel, 0, indexOf(parameterWithLabel, ":  "));
		lut = Dialog.getChoice;
		revLut = Dialog.getCheckbox;
		stroke = Dialog.getNumber;
		alpha = pad(toHex(255*Dialog.getNumber/100));
		unitLabel = Dialog.getChoice();
		rangeS = Dialog.getString; /* changed from original to allow negative values - see below */
		numLabels = Dialog.getNumber;
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
		addSummary = Dialog.getCheckbox;
		statsChoiceLines =  minOf(8, Dialog.getNumber);
		if (statsChoiceLines==0) addSummary = false;
//
	if (rotLegend && rampChoice==rampH) rampH = imageHeight - 2 * fontSize; /* tweaks automatic height selection for vertical legend */
	else rampH = rampChoice;
//		
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
	for (i=0; i<items; i++) values[i]= getResult(parameter,i);
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
	
	decPlaces = -1;	/* defaults to scientific notation */
	if (dpChoice=="Auto")
		decPlaces = autoCalculateDecPlaces(decPlaces);
	if (dpChoice=="Manual") 
		decPlaces=getNumber("Choose Number of Decimal Places", 0);
	
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
		yPos = floor(fontSize/2 + rampH - i*step + 1.5*fontSize);
		rampLabel= min + (max-min)/(numLabels-1) * i;
		rampLabelString = removeTrailingZerosAndPeriod(d2s(rampLabel,decPlaces));
			
		/*Now add overrun text labels at the top and/or bottom of the ramp if the true data extends beyond the ramp range */
		if (i==0 && min>arrayMin) {
			rampExt = removeTrailingZerosAndPeriod(d2s(arrayMin,decPlaces+1)); // adding 1 to dp makes sure range is different
			rampLabelString = rampExt + "-" + rampLabelString; 
		}
		if (i==numLabels-1 && max<arrayMax) {
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
	if (minmaxLines || statsRampLines) {
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
	/* now use a mask to create black outline around white text to stand out against ramp colors */
	rampOutlineStroke = round(rampLW/2);
	setThreshold(0, 128);
	setOption("BlackBackground", false);
	run("Convert to Mask");
	selectWindow(tR);
	run("Select None");
	getSelectionFromMask("label_mask");
	run("Enlarge...", "enlarge=[rampOutlineStroke] pixel");
	setBackgroundFromColorName("#"+roiColors[255]); // functionoutlineColor]")
	setBackgroundFromColorName("black"); // functionoutlineColor]")
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
	
/*	parse symbols in unit and draw final label below ramp */
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
		if (values[i]<=min)
			lutIndex= 0;
		else if (values[i]>max)
			lutIndex= 255;
		else if (!revLut)
			lutIndex= round(255 * (values[i] - min) / (max - min));
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
	}
//
	roiManager("show all without labels");
	run("Flatten");
	if (originalImageDepth==8 && lut=="Grays") run("8-bit"); // restores gray if all gray settings
	flatImage = getTitle();
// display result
	if (addSummary) {
		/*	Now to format summary 
			First: set default label settings */
		lineSpacing = 1.1;
		outlineStroke = 8; /* default outline stroke: % of font size */
		shadowDrop = 16;  /* default outer shadow drop: % of font size */
		dIShO = 5; /* default inner shadow drop: % of font size */
		offsetX = round(1 + imageWidth/150); /* default offset of label from edge */
		offsetY = round(1 + imageHeight/150); /* default offset of label from edge */
		selColor = "white";
		outlineColor = "black"; 	
		originalImageDepth = bitDepth();
		paraLabFontSize = round((imageHeight+imageWidth)/45);
		statsLabFontSize = round((imageHeight+imageWidth)/60);
		decPlacesSummary = autoCalculateDecPlacesFromValueOnly(arrayMean);
		dpLab = decPlacesSummary+2; /* Increase dp over ramp label auto setting */
		coeffVar = d2s(coeffVar,dpLab);
		arrayMeanLab = d2s(arrayMean,dpLab);
		coeffVarLab = d2s((100/arrayMean)*arraySD,dpLab);
		arraySDLab = d2s(arraySD,dpLab);
		arrayMinLab = d2s(arrayMin,dpLab);
		arrayMaxLab = d2s(arrayMax,dpLab);
		arrayMedianLab = d2s(arrayMedian,dpLab);
		
		
		/* recombine units and labels that were used in Ramp */
		if (unitLabel!="") paraLabel = parameter + ", " + unitLabel;
		else paraLabel = parameter; /* note paraLabel is compact for fitting at top of ramp */
		/* Then Dialog . . . */
		Dialog.create("Feature Label Formatting Options");
			if (lut!="Grays")
				colorChoice = newArray("white", "black", "light_gray", "gray", "dark_gray", "aqua_modern", "blue_modern", "garnet", "gold", "green_modern", "orange_modern", "pink_modern", "red_modern", "violet_modern", "yellow_modern"); 
			else colorChoice = newArray("white", "black", "light_gray", "gray", "dark_gray");
			Dialog.addChoice("Font label color:", colorChoice, colorChoice[0]);
			fontStyleChoice = newArray("bold", "bold antialiased", "italic", "bold italic", "unstyled");
			Dialog.addChoice("Font style:", fontStyleChoice, fontStyleChoice[1]);
			fontNameChoice = newArray("SansSerif", "Serif", "Monospaced");
			Dialog.addChoice("Font name:", fontNameChoice, fontNameChoice[0]);
			Dialog.addNumber("Line spacing", lineSpacing,0,3,"");
			Dialog.addNumber("Outline stroke:", outlineStroke,0,3,"% of font size");
			Dialog.addChoice("Outline (background) color:", colorChoice, colorChoice[1]);
			Dialog.addNumber("Shadow drop: ±", shadowDrop,0,3,"% of font size");
			Dialog.addNumber("Shadow displacement right: ±", shadowDrop,0,3,"% of font size");
			Dialog.addNumber("Shadow Gaussian Blur:", floor(0.75 * shadowDrop),0,3,"% of font size");
			Dialog.addNumber("Shadow darkness \(darkest = 100%\):", 60,0,3,"%");
			Dialog.addMessage("The following \"Inner Shadow\" options do not change the Overlay scale bar");
			Dialog.addNumber("Inner shadow drop: ±", dIShO,0,3,"% of font size");
			Dialog.addNumber("Inner displacement right: ±", dIShO,0,3,"% of font size");
			Dialog.addNumber("Inner shadow mean blur:",floor(dIShO/2),1,2,"pixels");
			Dialog.addNumber("Inner shadow darkness \(darkest = 100%\):", 20,0,3,"%");
			if (selectionExists) paraLocChoice = newArray("None", "Current Selection", "Top Left", "Top Right", "Center", "Bottom Left", "Bottom Right", "Center of New Selection");
			else paraLocChoice = newArray("None", "Top Left", "Top Right", "Center", "Bottom Left", "Bottom Right", "Center of New Selection"); 
			Dialog.addChoice("Location of summary:", paraLocChoice, paraLocChoice[1]);
			Dialog.addChoice("Parameter label: " + paraLabel, newArray("Yes", "No"), "No");
			Dialog.addNumber("Image label font size:", paraLabFontSize);			
			statsChoice = newArray("None", "Dashed line:  ---", "Number of objects:  "+items,  "Mean:  "+arrayMeanLab, "Median:  "+arrayMedianLab, "StdDev:  "+arraySDLab, "CoeffVar:  "+coeffVarLab, "Min-Max:  "+arrayMinLab+"-"+arrayMaxLab, "Minimum:  "+arrayMinLab, "Maximum:  "+arrayMaxLab, "Long dashed underline:  ___");
			// statsChoiceLines = 6; /* 6 choices of stats lines */
			for (i=0; i<statsChoiceLines; i++)
				Dialog.addChoice("Statistics label line "+(i+1)+":", statsChoice, statsChoice[i+3]);
			Dialog.addNumber("Statistics label font size:", statsLabFontSize);			
			
			Dialog.show();
			selColor = Dialog.getChoice();
			fontStyle = Dialog.getChoice();
			fontName = Dialog.getChoice();
			lineSpacing = Dialog.getNumber();
			outlineStroke = Dialog.getNumber();
			outlineColor = Dialog.getChoice();
			shadowDrop = Dialog.getNumber();
			shadowDisp = Dialog.getNumber();
			shadowBlur = Dialog.getNumber();
			shadowDarkness = Dialog.getNumber();
			innerShadowDrop = Dialog.getNumber();
			innerShadowDisp = Dialog.getNumber();
			innerShadowBlur = Dialog.getNumber();
			innerShadowDarkness = Dialog.getNumber();
			paraLabPos = Dialog.getChoice();
			paraLabChoice = Dialog.getChoice();
			paraLabFontSize =  Dialog.getNumber();
			statsLabLine = newArray(statsChoiceLines);
			for (i=0; i<statsChoiceLines; i++)
				statsLabLine[i] = Dialog.getChoice();
			statsLabFontSize =  Dialog.getNumber();
			
			selectWindow(t);
			
			shadowDarkness = (255/100) * (abs(shadowDarkness));
			innerShadowDarkness = (255/100) * (100 - (abs(innerShadowDarkness)));
			
		if (fontStyle=="unstyled") fontStyle="";
		labLines = 0; /* parameter label line if desired */
		statsLines = 0; /* statistics lines */
		if (paraLabPos!="None") {
			/* Count lines of summary label */
			if (paraLabChoice=="Yes") labLines = 1;
			/* Reduce decimal places - but not as much as ramp labels */
			statsLabLineText = newArray(statsChoiceLines); /* up to 6 lines of statistics */
			setFont(fontName, statsLabFontSize, fontStyle);
			longestStringWidth = 0;
			for (i=0; i<statsChoiceLines; i++) {
				// if (statsLabLine[i]!="None") statsLines = statsLines + 1;
				if (statsLabLine[i]!="None") {
					statsLines = i + 1;
					statsLabLine[i] = substring(statsLabLine[i], 0, indexOf(statsLabLine[i], ":  "));
					if (statsLabLine[i]=="Dashed line") statsLabLineText[i] = "--------";
					else if (statsLabLine[i]=="Number of objects") statsLabLineText[i] = "Objects = " + items;
					else if (statsLabLine[i]=="Mean") statsLabLineText[i] = "Mean = " + arrayMeanLab + " " + unitLabel;
					else if (statsLabLine[i]=="Median") statsLabLineText[i] = "Median = " + arrayMedianLab + " " + unitLabel;
					else if (statsLabLine[i]=="StdDev") statsLabLineText[i] = "Std.Dev. = " + arraySDLab + " " + unitLabel;
					else if (statsLabLine[i]=="CoeffVar") statsLabLineText[i] = "Coeff.Var. = " + coeffVarLab + "%";
					else if (statsLabLine[i]=="Min-Max") statsLabLineText[i] = "Range = " + arrayMinLab + " - " + arrayMaxLab + " " + unitLabel;
					else if (statsLabLine[i]=="Minimum") statsLabLineText[i] = "Minimum = " + arrayMinLab + " " + unitLabel;
					else if (statsLabLine[i]=="Maximum") statsLabLineText[i] = "Maximum = " + arrayMaxLab + " " + unitLabel;
					else if (statsLabLine[i]=="Long Dashed Underline:  ___") statsLabLineText[i] = "__________";
					if (unitLabel==fromCharCode(0x00B0)) statsLabLineText[i] = replace(statsLabLineText[i], " "+ fromCharCode(0x00B0), fromCharCode(0x00B0)); // tweak to remove space before degree symbol					if (getStringWidth(statsLabLineText[i])>longestStringWidth) longestStringWidth = getStringWidth(statsLabLineText[i]);
					if (getStringWidth(statsLabLineText[i])>longestStringWidth) longestStringWidth = getStringWidth(statsLabLineText[i]);
				}
			}
			linesSpace = 1.2 * ((labLines*paraLabFontSize)+(statsLines*statsLabFontSize));
			unitLabel= cleanLabel(unitLabel);		
			if (paraLabPos!="None") {		
				/* recombine units and labels that were used in Ramp */
				if (unitLabel!="") paraLabel = parameterLabel + ", " + unitLabel;
				else paraLabel = parameterLabel;
				if (paraLabChoice=="Yes") {
					paraLabel = expandLabel(paraLabel);
					setFont(fontName, paraLabFontSize, fontStyle);
					if (getStringWidth(paraLabel)>longestStringWidth) longestStringWidth = getStringWidth(paraLabel);
				}
				if (paraLabPos == "Top Left") {
					selEX = offsetX;
					selEY = offsetY;
				} else if (paraLabPos == "Top Right") {
					selEX = imageWidth - longestStringWidth - offsetX;
					selEY = offsetY;
				} else if (paraLabPos == "Center") {
					selEX = round((imageWidth - longestStringWidth)/2);
					selEY = round((imageHeight - linesSpace)/2);
				} else if (paraLabPos == "Bottom Left") {
					selEX = offsetX;
					selEY = imageHeight - offsetY - linesSpace; 
				} else if (paraLabPos == "Bottom Right") {
					selEX = imageWidth - longestStringWidth - offsetX;
					selEY = imageHeight - offsetY - linesSpace;
				} else if (paraLabPos == "Center of New Selection"){
					batchOn = is("Batch Mode");
				if (batchOn) setBatchMode("exit & display"); /* need to see what you are selecting */
				setTool("rectangle");
					msgtitle="Location for the summary labels...";
					msg = "Draw a box in the image where you want to center the summary labels...";
					waitForUser(msgtitle, msg);
					getSelectionBounds(newSelEX, newSelEY, newSelEWidth, newSelEHeight);
					selEX = newSelEX + round((newSelEWidth/2) - longestStringWidth/2);
					selEY = newSelEY + round((newSelEHeight/2) - (linesSpace/2));
					if (batchOn) setBatchMode(true); /* return to original batch mode */
				} else if (paraLabPos == "Current Selection"){
					selEX = originalSelEX + round((originalSelEWidth/2) - longestStringWidth/2);
					selEY = originalSelEY + round((originalSelEHeight/2) - (linesSpace/2));
				}
				// run("Select None");
				if (selEY<=1.5*paraLabFontSize)
					selEY += paraLabFontSize;
				if (selEX<offsetX) selEX = offsetX;
				endX = selEX + longestStringWidth;
				if ((endX+offsetX)>imageWidth) selEX = imageWidth - longestStringWidth - offsetX;
				paraLabelX = selEX;
				paraLabelY = selEY;
				setColorFromColorName("white");
			}
		if (is("Batch Mode")==false) setBatchMode(true);
		newImage("label_mask", "8-bit black", imageWidth, imageHeight, 1);
		// roiManager("show none");
		roiManager("deselect");
		// run("Select None");
			/* Draw summary over top of labels */
			if (paraLabPos!="None") {
				if (paraLabChoice=="Yes") {
					setFont(fontName,paraLabFontSize, fontStyle);
					drawString(paraLabel, paraLabelX, paraLabelY);
					paraLabelY += round(1.2 * paraLabFontSize);
				}
				setFont(fontName,statsLabFontSize, fontStyle);
				for (i=0; i<statsLines; i++) {
					// if (statsLabLine[i]!="None") statsLines = statsLines + 1;
					if (statsLabLine[i]!="None") {
						drawString(statsLabLineText[i], paraLabelX, paraLabelY);
						paraLabelY += round(1.2 * statsLabFontSize);	
					}
				}
			}
			
			negAdj = 0.5;  /* negative offsets appear exaggerated at full displacement */
			if (shadowDrop<0) shadowDrop *= negAdj;
			if (shadowDisp<0) shadowDisp *= negAdj;
			if (shadowBlur<0) shadowBlur *= negAdj;
			if (innerShadowDrop<0) innerShadowDrop *= negAdj;
			if (innerShadowDisp<0) innerShadowDisp *= negAdj;
			if (innerShadowBlur<0) innerShadowBlur *= negAdj;
			
			fontPC = statsLabFontSize/100;
			outlineStroke = round(fontPC * outlineStroke);
			shadowDrop = floor(fontPC * shadowDrop);
			shadowDisp = floor(fontPC * shadowDisp);
			shadowBlur = floor(fontPC * shadowBlur);
			innerShadowDrop = floor(fontPC * innerShadowDrop);
			innerShadowDisp = floor(fontPC * innerShadowDisp);
			innerShadowBlur = floor(fontPC * innerShadowBlur);
					
			roiManager("show none");
			setThreshold(0, 128);
			setOption("BlackBackground", false);
			run("Convert to Mask");
			/*
			Create drop shadow if desired */
			if (shadowDrop!=0 || shadowDisp!=0 || shadowBlur!=0) {
				showStatus("Creating drop shadow for labels . . . ");
				newImage("shadow", "8-bit black", imageWidth, imageHeight, 1);
				getSelectionFromMask("label_mask");
				getSelectionBounds(selMaskX, selMaskY, selMaskWidth, selMaskHeight);
				setSelectionLocation(selMaskX+shadowDisp, selMaskY+shadowDrop);
				setBackgroundColor(shadowDarkness, shadowDarkness, shadowDarkness);
				run("Clear");
				getSelectionFromMask("label_mask");
				expansion = abs(shadowDisp) + abs(shadowDrop) + abs(shadowBlur);
				if (expansion>0) run("Enlarge...", "enlarge=[expansion] pixel");
				if (shadowBlur>0) run("Gaussian Blur...", "sigma=[shadowBlur]");
				run("Select None");
			}
		/*	Create inner shadow if desired */
			if (innerShadowDrop!=0 || innerShadowDisp!=0 || innerShadowBlur!=0) {
				showStatus("Creating inner shadow for labels . . . ");
				newImage("inner_shadow", "8-bit white", imageWidth, imageHeight, 1);
				getSelectionFromMask("label_mask");
				setBackgroundColor(innerShadowDarkness, innerShadowDarkness, innerShadowDarkness);
				run("Clear Outside");
				getSelectionBounds(selMaskX, selMaskY, selMaskWidth, selMaskHeight);
				setSelectionLocation(selMaskX-innerShadowDisp, selMaskY-innerShadowDrop);
				setBackgroundColor(innerShadowDarkness, innerShadowDarkness, innerShadowDarkness);
				run("Clear Outside");
				getSelectionFromMask("label_mask");
				expansion = abs(innerShadowDisp) + abs(innerShadowDrop) + abs(innerShadowBlur);
				if (expansion>0) run("Enlarge...", "enlarge=[expansion] pixel");
				if (innerShadowBlur>0) run("Mean...", "radius=[innerShadowBlur]"); /* Gaussian is too large */
				if (statsLabFontSize<12) run("Unsharp Mask...", "radius=0.5 mask=0.2"); /* A tweak to sharpen effect for small font sizes */
				imageCalculator("Max", "inner_shadow","label_mask");
				run("Select None");
				run("Invert");  /* create an image that can be subtracted - works better for color than min */
			}
			if (isOpen("shadow") && shadowDarkness>0)		
				imageCalculator("Subtract", flatImage,"shadow");
			else if (isOpen("shadow") && shadowDarkness<0)		
				imageCalculator("Add", flatImage,"shadow");
			run("Select None");
			/* Create outline around text */
			getSelectionFromMask("label_mask");
			run("Enlarge...", "enlarge=[outlineStroke] pixel");
			setBackgroundFromColorName(outlineColor); // functionoutlineColor]")
			run("Clear");
			run("Select None");
			/* Create text */
			getSelectionFromMask("label_mask");
			setBackgroundFromColorName(selColor);
			run("Clear");
			run("Select None");
			/* Create inner shadow or glow if requested */
			if (isOpen("inner_shadow") && innerShadowDarkness>0)
				imageCalculator("Subtract", flatImage,"inner_shadow");
			else if (isOpen("inner_shadow") && innerShadowDarkness<0)
				imageCalculator("Add", flatImage,"inner_shadow");
	
			closeImageByTitle("shadow");
			closeImageByTitle("inner_shadow");
			closeImageByTitle("label_mask");
		}		
		selectWindow(flatImage);	
	}
/*	
		End of Optional Summary section
*/
	if (countNaN!=0)
		print("\n>>>> ROI Color Coder:\n"
			+ "Some values from the \""+ parameter +"\" column could not be retrieved.\n"
			+ countNaN +" ROI(s) were labeled with a default color.");
	rename(tN + "_" + parameterLabel + "_coded");
	tNP = getTitle();
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
		srW = getWidth;
		comboW = srW + imageWidth;
		selectWindow(tNP);
		if (createCombo=="Combine Scaled Ramp with New Image" || createCombo=="Combine Ramp with New Image") run("Duplicate...", "title=temp_combo");
		run("Canvas Size...", "width="+comboW+" height="+imageHeight+" position=Top-Left");
		makeRectangle(imageWidth, round((imageHeight-canvasH)/2), srW, imageHeight);
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Scaled Ramp with New Image") run("Image to Selection...", "image=scaled_ramp opacity=100");
		if (createCombo=="Combine Ramp with Current" || createCombo=="Combine Ramp with New Image") run("Image to Selection...", "image=" + tR + " opacity=100");
		run("Flatten");
		if (originalImageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
		rename(tNP + "+ramp");
		closeImageByTitle("scaled_ramp");
		closeImageByTitle("temp_combo");
		if (createCombo=="Combine Scaled Ramp with Current" || createCombo=="Combine Ramp with Current") closeImageByTitle(tNP);
	}
	else run("Flatten");
	if (originalImageDepth==8 && lut=="Grays") run("8-bit"); /* restores gray if all gray settings */
	restoreSettings;
	setBatchMode("exit & display");	
	showStatus("BAR ROI Color + Summary Macro Finished");
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
	function autoCalculateDecPlacesFromValueOnly(dP){
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
		nROIs = roiManager("count");
		nRES = nResults;
		if (nROIs==0)  {
			Dialog.create("No ROI");
			Dialog.addCheckbox("Run Analyze-particles to generate roiManager values?", true);
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
			else restoreExit();
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
//
	/* Macro Color Functions */
//
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
	function pad(n) {
		n= toString(n); if (lengthOf(n)==1) n= "0"+n; return n;
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
	function unCleanLabel(string) { /* v161104 This function replaces special characters with standard characters for file system compatible filenames */
		string= replace(string, fromCharCode(178), "\\^2"); /* superscript 2 */
		string= replace(string, fromCharCode(179), "\\^3"); /* superscript 3 UTF-16 (decimal) */
		string= replace(string, fromCharCode(0x207B) + fromCharCode(185), "\\^-1"); /* superscript -1 */
		string= replace(string, fromCharCode(0x207B) + fromCharCode(178), "\\^-2"); /* superscript -2 */
		string= replace(string, fromCharCode(181), "u"); /* micrometer units */
		string= replace(string, fromCharCode(197), "Angstrom"); /* angstrom symbol */
		string= replace(string, fromCharCode(0x2009)+"fromCharCode(0x00B0)", "deg"); /* replace thin spaces degrees combination */
		string= replace(string, fromCharCode(0x2009), "_"); /* replace thin spaces  */
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
	function writeLabel(labelColor){
		setColorFromColorName(labelColor);
		drawString(finalLabel, finalLabelX, finalLabelY); 
	}
