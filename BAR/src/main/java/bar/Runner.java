package bar;

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.util.Map;
import java.util.concurrent.Future;

import javax.script.ScriptException;

import net.imagej.ImageJ;

import org.scijava.Context;
import org.scijava.command.Command;
import org.scijava.log.LogService;
import org.scijava.plugin.Parameter;
import org.scijava.plugin.Plugin;
import org.scijava.script.ScriptModule;
import org.scijava.script.ScriptService;
import org.scijava.ui.UIService;

import ij.IJ;
import ij.plugin.Macro_Runner;

/** Runs a JARified script **/
@Plugin(type = Command.class)
public class Runner {

	@Parameter
	private Context context;

	@Parameter
	private ScriptService scriptService;

	@Parameter
	private LogService logService;

	@Parameter
	private UIService uiService;

	@Parameter
	private Boolean silent;

	@Parameter
	private Boolean loaded;

	@Parameter
	private String exitStatus;

	/* exit status */
	private static final String WAS_CANCELED = "canceled";
	private static final String WAS_DONE = "done";
	private static final String WAS_LOADED = "loaded";
	private static final String IO_ERROR = "io error";
	private static final String EXCEPTION = "exception";

	/** Default constructor-based dependency injection */
	public Runner(final Context context) {
		context.inject(this);
		setSilent(false);
	}

	/**
	 * Constructor relying on IJ1.
	 *
	 * @param silent
	 *            if errors should be ignored by the {@link LogService}
	 */
	public Runner(final boolean silent) {
		if (context == null)
			context = (Context) IJ.runPlugIn("org.scijava.Context", "");
		if (scriptService == null)
			scriptService = context.getService(ScriptService.class);
		if (logService == null)
			logService = context.getService(LogService.class);
		if (uiService == null)
			uiService = context.getService(UIService.class);
		setSilent(silent);
	}

	/** Debug method **/
	public static void main(final String... args) throws Exception {
		final ImageJ ij = net.imagej.Main.launch(args);
		final Runner runner = new Runner(ij.context());
		runner.runScript("Data_Analysis", "Distribution_Plotter.ijm");
	}

	/**
	 * Runs a script from an InputStream.
	 *
	 * @param in
	 *            the {@link InputStream} loading the script to be executed
	 * @param filename
	 *            the script filename (or at least its extension)
	 */
	public void runScript(final InputStream in, final String filename) {
		runScript(in, filename, null);
	}

	/**
	 * Runs a (JARified) BAR script.
	 *
	 * @param path
	 *            the path of the BAR script to be executed, e.g,
	 *            {@code /scripts/BAR/Data_Analysis/Distribution_Plotter.ijm};
	 */
	public void runScript(final String path) {
		final InputStream in = Utils.class.getResourceAsStream(path);
		runScript(in, path, null);
	}

	/**
	 * Runs a (JARified) BAR script.
	 *
	 * @param path
	 *            the path of the BAR script to be executed, e.g,
	 *            {@code /scripts/BAR/Data_Analysis/Distribution_Plotter.ijm};
	 * @param inputMap
	 *            see {@link ScriptService#run(String, Reader, boolean, Map)}
	 */
	public void runScript(final String path, final Map<String, Object> inputMap) {
		final InputStream in = Utils.class.getResourceAsStream(path);
		runScript(in, path, inputMap);
	}

	/**
	 * Runs a (JARified) BAR script.
	 *
	 * @param dir
	 *            the script directory, i.e., the subdirectory in the BAR jar
	 *            relative to {@code /scripts/BAR/}
	 * @param file
	 *            the script filename
	 * @param inputMap
	 *            see {@link ScriptService#run(String, Reader, boolean, Map)}
	 */
	public void runScript(final String dir, final String file, final Map<String, Object> inputMap) {
		final String path = "/scripts/BAR/" + dir + "/" + file;
		runScript(path, inputMap);
	}

	/**
	 * Runs a (JARified) BAR script.
	 *
	 * @param dir
	 *            the script directory, i.e., the subdirectory in the BAR jar
	 *            relative to {@code /scripts/BAR/}
	 * @param file
	 *            the script filename
	 */
	public void runScript(final String dir, final String file) {
		final String path = "/scripts/BAR/" + dir + "/" + file;
		runScript(path);
	}

	/**
	 * Runs a script from a jar file.
	 *
	 * @param in
	 *            the {@link InputStream} loading the script to be executed
	 * @param filename
	 *            the script filename (or at least its extension)
	 * @param inputMap
	 *            see {@link ScriptService#run(String, Reader, boolean, Map)}
	 */
	public void runScript(final InputStream in, final String filename, final Map<String, Object> inputMap) {
		try {
			if (in == null) {
				error("Could not find " + filename, IO_ERROR);
				return;
			}
			final Reader reader = new InputStreamReader(in);
			setLoaded(true);
			final Future<ScriptModule> fsm = scriptService.run(filename, reader, true, inputMap);
			if (fsm.isCancelled())
				setStatus(WAS_CANCELED);
			else if (fsm.isDone())
				setStatus(WAS_DONE);
		} catch (final IOException e) {
			error("There was an error reading " + filename, IO_ERROR);
		} catch (final ScriptException e) {
			error("There was an error running " + filename + ": " + e.getMessage(), EXCEPTION);
		}
	}

	/**
	 * Legacy method that supports IJ1 macros that do not use script parameters.
	 * Ported from {@link Macro_Runner#runMacroFromJar(String, String)}.
	 *
	 * @param path
	 *            the path to the IJ1 macro in the BAR file relative to
	 *            {@code /scripts/BAR/}
	 * @param arg
	 *            the argument string to be retrieved through the IJ1 built-in
	 *            macro function {@code getArgument()}
	 */
	public void runIJ1Macro(final String path, final String arg) {
		String macro = null;
		try {
			@SuppressWarnings("resource")
			final InputStream is = Utils.class.getResourceAsStream("/scripts/BAR/" + path);
			if (is == null) {
				error("Could not find " + path, IO_ERROR);
				return;
			}
			@SuppressWarnings("resource")
			final InputStreamReader isr = new InputStreamReader(is);
			setLoaded(true);
			final StringBuffer sb = new StringBuffer();
			final char[] b = new char[8192];
			int n;
			while ((n = isr.read(b)) > 0)
				sb.append(b, 0, n);
			macro = sb.toString();
			is.close();
		} catch (final IOException e) {
			error("There was an error reading " + path, IO_ERROR);
		}
		setStatus((macro == null) ? EXCEPTION : (new Macro_Runner()).runMacro(macro, arg));
	}

	private void error(final String msg, final String status) {
		if (!silent)
			logService.error(msg);
		setStatus(status);
		setLoaded(false);
	}

	private void setStatus(final String status) {
		this.exitStatus = status;
	}

	private void setLoaded(final boolean loaded) {
		if (loaded)
			setStatus(WAS_LOADED);
		this.loaded = loaded;
	}

	/**
	 * return {@code true} if the {@link LogService} is not logging errors. Note
	 * that passing invalid parameters to scripts may still trigger Console
	 * warnings.
	 */
	public Boolean isSilent() {
		return silent;
	}

	/**
	 * Should {@link LogService} display errors?
	 *
	 * @param silent
	 *            if {@code true} errors are ignored silently. Note that passing
	 *            invalid parameters to scripts may still trigger Console
	 *            warnings.
	 */
	public void setSilent(final Boolean silent) {
		this.silent = silent;
	}

	/**
	 * Assesses if last script was loaded successfully
	 *
	 * @return {@code true} if the last run script could not be loaded otherwise
	 *         {@code false}
	 */
	public boolean scriptLoaded() {
		return loaded;
	}

	/**
	 * @return the exit status: {@code cancelled}, {@code done},
	 *         {@code exception}, {@code loaded}, {@code io error}, or in the
	 *         case of IJ1 macros loaded through legacy mechanisms the String
	 *         value returned by the
	 *         {@link Macro_Runner#runMacro(String, String)}
	 */
	public String getStatus() {
		return exitStatus;
	}

}
