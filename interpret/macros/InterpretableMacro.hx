package interpret.macros;

import sys.io.File;
import sys.FileSystem;
import haxe.macro.TypeTools;
import haxe.io.Path;
import haxe.macro.Printer;
import haxe.macro.Context;
import haxe.macro.Expr;

using StringTools;

class InterpretableMacro {

    macro static public function build():Array<Field> {

        var fields = Context.getBuildFields();

        var currentPos = Context.currentPos();

#if (!display && !completion)

        var hasFieldsWithInterpretMeta = false;

        var localClass = Context.getLocalClass().get();
        // add a meta to prevent that class to be altered by dce, and depending classes
        localClass.meta.add(":keepSub", [], currentPos);

        var classHasInterpretMeta = hasInterpretMeta(localClass.meta.get());

        var filePath = Context.getPosInfos(localClass.pos).file;
        if (!Path.isAbsolute(filePath)) {
            filePath = Path.join([Sys.getCwd(), filePath]);
        }
        filePath = Path.normalize(filePath);

        var classPack:Array<String> = localClass.pack;
        var className:String = localClass.name;

        var extraFields:Array<Field> = null;

        var dynCallBrokenNames:Array<String> = [];

        for (field in fields) {

            if (classHasInterpretMeta || hasInterpretMeta(field.meta)) {

                switch (field.kind) {
                    case FFun(fn):
                        hasFieldsWithInterpretMeta = true;
                        if (extraFields == null) extraFields = [];

                        if (field.name == 'new') {
                            if (!classHasInterpretMeta || hasInterpretMeta(field.meta)) {
                                throw "@interpret is not allowed on constructor";
                            }
                            else {
                                continue;
                            }
                        }

                        // Is it a static call?
                        var isStatic = field.access.indexOf(AStatic) != -1;

                        // Do we return something or is this a Void method?
                        var isVoidRet = false;
                        if (fn.ret == null) {
                            // Need to check content to find return type
                            isVoidRet = true; 
                            var printer = new haxe.macro.Printer();
                            var lines = printer.printExpr(fn.expr).split("\n");
                            for (i in 0...lines.length) {
                                var line = lines[i];
                                if (line.ltrim().startsWith('return ')) {
                                    isVoidRet = false;
                                    break;
                                }
                                else if (line.trim() == 'return;') {
                                    break;
                                }
                            }
                        }
                        else {
                            switch (fn.ret) {
                                case TPath(p):
                                    if (p.name == 'Void') {
                                        isVoidRet = true;
                                    }
                                default:
                            }
                        }

                        var argTypes = [];
                        for (arg in fn.args) {
                            var type = Context.resolveType(arg.type, field.pos);
                            var typeStr = TypeTools.toString(type).replace(' ', '');
                            if (arg.opt) typeStr = '?' + typeStr;
                            argTypes.push(typeStr);
                        }

                        // Compute dynamic call args
                        var dynCallArgsArray = [for (arg in fn.args) macro $i{arg.name}];
                        var dynCallArgs = fn.args.length > 0 ? macro $a{dynCallArgsArray} : macro null;
                        var dynCallName = field.name;
                        var dynCallBrokenName = '__interpretBroken_' + field.name;
                        
                        dynCallBrokenNames.push(dynCallBrokenName);

                        extraFields.push({
                            pos: currentPos,
                            name: dynCallBrokenName,
                            kind: FVar(macro :Bool, macro false),
                            access: [APrivate, AStatic],
                            doc: '',
                            meta: [{
                                name: ':noCompletion',
                                params: [],
                                pos: currentPos
                            }]
                        });

                        // Ensure expr is surrounded with a block
                        switch (fn.expr.expr) {
                            case EBlock(exprs):
                            default:
                                fn.expr.expr = EBlock([{
                                    pos: fn.expr.pos,
                                    expr: fn.expr.expr
                                }]);
                        }

                        // Compute (conditional) dynamic call expr
                        var dynCallExpr = switch [isStatic, isVoidRet] {
                            case [true, true]: macro if (__interpretClass != null) {
                                if (!$i{dynCallBrokenName}) {
                                    if (__interpretClass.skipFields == null || !__interpretClass.skipFields.exists($v{dynCallName})) {
                                        try {
                                            __interpretClass.call($v{dynCallName}, $dynCallArgs, true, $v{argTypes});
                                            return;
                                        }
                                        catch (e:Dynamic) {
                                            interpret.Env.catchInterpretableException(e, __interpretClass);
                                            $i{dynCallBrokenName} = true;
                                        }
                                    }
                                }
                            };
                            case [true, false]: macro if (__interpretClass != null) {
                                if (!$i{dynCallBrokenName}) {
                                    if (__interpretClass.skipFields == null || !__interpretClass.skipFields.exists($v{dynCallName})) {
                                        try {
                                            var res = __interpretClass.call($v{dynCallName}, $dynCallArgs, true, $v{argTypes});
                                            return res;
                                        }
                                        catch (e:Dynamic) {
                                            interpret.Env.catchInterpretableException(e, __interpretClass);
                                            $i{dynCallBrokenName} = true;
                                        }
                                    }
                                }
                            };
                            case [false, true]: macro if (__interpretClass != null) {
                                if (!$i{dynCallBrokenName}) {
                                    if (__interpretClass.skipFields == null || !__interpretClass.skipFields.exists($v{dynCallName})) {
                                        try {
                                            if (__interpretInstance == null || __interpretInstance.dynamicClass != __interpretClass) {
                                                __interpretInstance = __interpretClass.createInstance(null, this);
                                            }
                                            __interpretInstance.call($v{dynCallName}, $dynCallArgs, true, $v{argTypes});
                                            return;
                                        }
                                        catch (e:Dynamic) {
                                            interpret.Env.catchInterpretableException(e, __interpretClass, __interpretInstance);
                                            $i{dynCallBrokenName} = true;
                                        }
                                    }
                                }
                            };
                            case [false, false]: macro if (__interpretClass != null) {
                                if (!$i{dynCallBrokenName}) {
                                    if (__interpretClass.skipFields == null || !__interpretClass.skipFields.exists($v{dynCallName})) {
                                        try {
                                            if (__interpretInstance == null || __interpretInstance.dynamicClass != __interpretClass) {
                                                __interpretInstance = __interpretClass.createInstance(null, this);
                                            }
                                            var res = __interpretInstance.call($v{dynCallName}, $dynCallArgs, true, $v{argTypes});
                                            return res;
                                        }
                                        catch (e:Dynamic) {
                                            interpret.Env.catchInterpretableException(e, __interpretClass, __interpretInstance);
                                            $i{dynCallBrokenName} = true;
                                        }
                                    }
                                }
                            };
                        }

                        // Add dynamic call expr
                        switch (fn.expr.expr) {
                            case EBlock(exprs):
                                exprs.unshift(dynCallExpr);
                            default:
                        }

                    default:
                        if (!classHasInterpretMeta || hasInterpretMeta(field.meta)) {
                            throw "@interpret meta only works on functions";
                        }
                }
            }

        }
#end

        fields.push({
            pos: currentPos,
            name: 'interpretWillReloadClass',
            kind: FVar(macro :interpret.DynamicClass->Void, macro null),
            access: [APublic, AStatic],
            doc: 'If provided, will be called right before this interpretable class is reloaded. If any, provides the dynamic class previously used as argument, before it is replaced by a new one.',
            meta: []
        });

        fields.push({
            pos: currentPos,
            name: 'interpretDidReloadClass',
            kind: FVar(macro :interpret.DynamicClass->Void, macro null),
            access: [APublic, AStatic],
            doc: 'If provided, will be called right after this interpretable class is reloaded. Provides the new dynamic class that has just been loaded as argument.',
            meta: []
        });

#if (!display && !completion)

        if (hasFieldsWithInterpretMeta) {

            // Add reset state
            //
            var resetBrokenCalls = [];
            for (dynCallBrokenName in dynCallBrokenNames) {
                resetBrokenCalls.push(macro $i{dynCallBrokenName} = false);
            }

            fields.push({
                pos: currentPos,
                name: '__interpretResetState',
                kind: FFun({
                    args: [],
                    ret: macro :Void,
                    expr: {
                        expr: EBlock(resetBrokenCalls),
                        pos: currentPos
                    }
                }),
                access: [APrivate, AStatic],
                doc: '',
                meta: [{
                    name: ':noCompletion',
                    params: [],
                    pos: currentPos
                }]
            });

            // Add dynamic class field
            fields.push({
                pos: currentPos,
                name: '__interpretClass',
                kind: FVar(macro :interpret.DynamicClass, macro null),
                access: [APrivate, AStatic],
                doc: '',
                meta: [{
                    name: ':noCompletion',
                    params: [],
                    pos: currentPos
                }]
            });

            // Add dynamic instance field
            fields.push({
                pos: currentPos,
                name: '__interpretInstance',
                kind: FVar(
                    macro :interpret.DynamicInstance,
                    macro null
                ),
                access: [APrivate],
                doc: '',
                meta: [{
                    name: ':noCompletion',
                    params: [],
                    pos: currentPos
                }]
            });

            // Keep original class content
            var fileContent:String = null;
            if (FileSystem.exists(filePath) && !FileSystem.isDirectory(filePath)) {
                fileContent = File.getContent(filePath);
            }
            fields.push({
                pos: currentPos,
                name: '__interpretOriginalContent',
                kind: FVar(
                    macro :String,
                    macro $v{fileContent}
                ),
                access: [AStatic, APrivate],
                doc: '',
                meta: [{
                    name: ':noCompletion',
                    params: [],
                    pos: currentPos
                }]
            });

            #if interpret_watch
            // Add watcher
            fields.push({
                pos: currentPos,
                name: '__interpretWatch',
                kind: FVar(
                    macro :interpret.LiveReload,
                    macro new interpret.LiveReload($v{filePath}, function(content:String) {
                        //trace('File changed at path ' + $v{filePath});
                        try {
                            if (interpretWillReloadClass != null) {
                                interpretWillReloadClass(__interpretClass);
                            }
                            __interpretClass = interpret.InterpretableTools.createInterpretClass($v{classPack}, $v{className}, content, __interpretOriginalContent);
                            if (__interpretClass == null) {
                                trace('[warning] Failed to reload interpretable class from file at path: ' + $v{filePath});
                            }
                            if (__interpretClass != null && interpretDidReloadClass != null) {
                                interpretDidReloadClass(__interpretClass);
                            }
                        }
                        catch (e:Dynamic) {
                            interpret.Errors.handleInterpretableError(e);
                            __interpretClass = null;
                        }
                        __interpretResetState();
                    })
                ),
                access: [APrivate, AStatic],
                doc: '',
                meta: [{
                    name: ':noCompletion',
                    params: [],
                    pos: currentPos
                }, {
                    name: ':keepSub',
                    params: [],
                    pos: currentPos
                }]
            });

            #end

        }

        if (extraFields != null) {
            for (field in extraFields) {
                fields.push(field);
            }
        } 

#end

        return fields;

    } //build

    static function complexTypeToString(type:ComplexType):String {

        var typeStr:String = null;

        if (type != null) {
            switch (type) {
                case TPath(p):
                    typeStr = p.name;
                    if (p.pack != null && p.pack.length > 0) {
                        typeStr = p.pack.join('.') + '.' + typeStr;
                    }
                default:
                    typeStr = 'Dynamic';
            }
        }
        else {
            typeStr = 'Dynamic';
        }

        return typeStr;
    }

    static function hasInterpretMeta(metas:Null<Metadata>):Bool {

        if (metas == null || metas.length == 0) return false;

        for (meta in metas) {
            if (meta.name == 'interpret') {
                return true;
            }
        }

        return false;

    } //hasInterpretMeta

} //InterpretableMacro
