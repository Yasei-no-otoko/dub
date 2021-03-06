/**
	Generator for direct RDMD builds.
	
	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.rdmd;

import dub.compilers.compiler;
import dub.generators.generator;
import dub.package_;
import dub.packagemanager;
import dub.project;
import dub.utils;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.string;
import stdx.process;

import vibecompat.core.file;
import vibecompat.core.log;
import vibecompat.inet.path;


class RdmdGenerator : ProjectGenerator {
	private {
		Project m_project;
		PackageManager m_pkgMgr;
	}
	
	this(Project app, PackageManager mgr)
	{
		m_project = app;
		m_pkgMgr = mgr;
	}
	
	void generateProject(GeneratorSettings settings)
	{
		//Added check for existance of [AppNameInPackagejson].d
		//If exists, use that as the starting file.
		auto mainsrc = getMainSourceFile(m_project);

		auto buildsettings = settings.buildSettings;
		m_project.addBuildSettings(buildsettings, settings.platform, settings.config);
		// do not pass all source files to RDMD, only the main source file
		buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(s => !s.endsWith(".d"))().array();
		buildsettings.addDFlags(["-w"/*, "-property"*/]);
		string dflags = environment.get("DFLAGS");
		if( dflags ){
			settings.buildType = "$DFLAGS";
			buildsettings.addDFlags(dflags.split());
		} else {
			addBuildTypeFlags(buildsettings, settings.buildType);
		}
		settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

		auto generate_binary = !buildsettings.dflags.canFind("-o-");

		// Create start script, which will be used by the calling bash/cmd script.
		// build "rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d" ~ application arguments
		// or with "/" instead of "\"
		Path run_exe_file;
		if( generate_binary ){
			if( settings.run ){
				import std.random;
				auto rnd = to!string(uniform(uint.min, uint.max)) ~ "-";
				auto tmp = environment.get("TEMP");
				if( !tmp.length ) tmp = environment.get("TMP");
				if( !tmp.length ){
					version(Posix) tmp = "/tmp";
					else tmp = ".";
				}
				buildsettings.targetPath = (Path(tmp)~".rdmd/source/").toNativeString();
				buildsettings.targetName = rnd ~ buildsettings.targetName;
				run_exe_file = Path(buildsettings.targetPath) ~ getTargetFileName(buildsettings, settings.platform);
			}
			settings.compiler.setTarget(buildsettings, settings.platform);
		}

		logDebug("Application output name is '%s'", getTargetFileName(buildsettings, settings.platform));

		string[] flags = ["--build-only", "--compiler="~settings.compilerBinary];
		flags ~= buildsettings.dflags;
		flags ~= (mainsrc).toNativeString();

		if( buildsettings.preGenerateCommands.length ){
			logInfo("Running pre-generate commands...");
			runCommands(buildsettings.preGenerateCommands);
		}

		if( buildsettings.postGenerateCommands.length ){
			logInfo("Running post-generate commands...");
			runCommands(buildsettings.postGenerateCommands);
		}

		if( buildsettings.preBuildCommands.length ){
			logInfo("Running pre-build commands...");
			runCommands(buildsettings.preBuildCommands);
		}

		if( settings.config.length ) logInfo("Building configuration "~settings.config~", build type "~settings.buildType);
		else logInfo("Building default configuration, build type "~settings.buildType);

		logInfo("Running rdmd...");
		logDebug("rdmd %s", join(flags, " "));
		auto rdmd_pid = spawnProcess("rdmd" ~ flags);
		auto result = rdmd_pid.wait();
		enforce(result == 0, "Build command failed with exit code "~to!string(result));

		if( buildsettings.postBuildCommands.length ){
			logInfo("Running post-build commands...");
			runCommands(buildsettings.postBuildCommands);
		}

		if( generate_binary ){
			// TODO: move to a common place - this is not generator specific
			if( buildsettings.copyFiles.length ){
				logInfo("Copying files...");
				foreach( f; buildsettings.copyFiles ){
					auto src = Path(f);
					auto dst = (run_exe_file.empty ? Path(buildsettings.targetPath) : run_exe_file.parentPath) ~ Path(f).head;
					logDebug("  %s to %s", src.toNativeString(), dst.toNativeString());
					try copyFile(src, dst, true);
					catch logWarn("Failed to copy to %s", dst.toNativeString());
				}
			}

			if( settings.run ){
				logInfo("Running %s...", run_exe_file.toNativeString());
				auto prg_pid = spawnProcess(run_exe_file.toNativeString() ~ settings.runArgs);
				result = prg_pid.wait();
				remove(run_exe_file.toNativeString());
				foreach( f; buildsettings.copyFiles )
					remove((run_exe_file.parentPath ~ Path(f).head).toNativeString());
				enforce(result == 0, "Program exited with code "~to!string(result));
			}
		}
	}
}

private Path getMainSourceFile(in Project prj)
{
	foreach( f; ["source/app.d", "src/app.d", "source/"~prj.name~".d", "src/"~prj.name~".d"])
		if( exists(f) )
			return Path(f);
	return Path("source/app.d");
}
